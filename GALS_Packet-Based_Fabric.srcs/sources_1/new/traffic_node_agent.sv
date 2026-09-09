`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 07/31/2026 04:52:00 PM
// Design Name:
// Module Name: traffic_node_agent
// Project Name:
// Target Devices:
// Tool Versions:
// Description:
//
// Dependencies:
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////


module traffic_node_agent #(
    parameter logic [3:0] DEST_ID    = 4'b0101,  // ปลายทางที่จะยิงไปหา {x,y}
    parameter logic [1:0] SRC_TAG    = 2'b01,    // ป้ายระบุตัวเองใน payload
    parameter int         PKT_FLITS  = 16,       // flit ต่อ 1 packet
    parameter int         VC_MODE    = 2,        // 0=VC0 only, 1=VC1 only, 2=สลับ
    parameter int         WINDOW_LOG = 24,       // 2^24 cycle ~ 0.24 s ที่ 70 MHz
    parameter int         WARMUP_LOG = 10,
    parameter int         DRAIN_LOG  = 12,
    parameter int         STUCK_LOG  = 16,       // เกณฑ์ตัดสิน: เงียบเกิน 2^STUCK_LOG
                                                 // cycle ระหว่าง S_RUN = ถือว่าตาย
    parameter int         GAP_W      = 24,       // ความกว้างของตัวจับช่องว่าง
                                                 // ต้องกว้างกว่าเกณฑ์ เพื่อให้ max_gap
                                                 // รายงานของจริงได้แม้ทะลุเกณฑ์ไปแล้ว
                                                 // ไม่งั้นจะรู้แค่ "เกิน" ไม่รู้ "เกินเท่าไร"
    parameter bit         TX_EN      = 1'b1      // 0 = ปิดขาส่ง ทำหน้าที่เป็น sink อย่างเดียว
                                                 //     ใช้ตอนทดสอบ hot-spot ที่ node ปลายทาง
)(
    input  logic clk,
    input  logic rst_n,

    // ---- จาก NoC เข้ามาที่ node นี้
    input  logic [7:0] rx_tdata,
    input  logic [3:0] rx_tdest,
    input  logic [1:0] rx_tid,
    input  logic       rx_tlast,
    input  logic       rx_tvalid,
    output logic [1:0] rx_tready,

    // ---- ออกจาก node นี้เข้า NoC
    output logic [7:0] tx_tdata,
    output logic [3:0] tx_tdest,
    output logic [1:0] tx_tid,
    output logic       tx_tlast,
    output logic       tx_tvalid,
    input  logic [1:0] tx_tready,

    // ---- สรุปผล ต่อออกไปข้างนอกจริง ไม่ใช่แค่ ILA tap
    // มี fanout จริงตรงนี้ synthesis จึงกวาดตัวนับทิ้งไม่ได้
    output logic       done,       // จบ window แล้ว ค่าถูกแช่ไว้
    output logic       err         // เจอ sequence ขาดตอนอย่างน้อย 1 ครั้ง
);

    localparam int IW = (PKT_FLITS > 1) ? $clog2(PKT_FLITS) : 1;

    typedef enum logic [1:0] {S_WARMUP, S_RUN, S_DRAIN, S_DONE} state_t;
    state_t state;

    logic [WARMUP_LOG-1:0] warm_cnt;
    logic [WINDOW_LOG-1:0] win_cnt;
    logic [DRAIN_LOG-1:0]  drain_cnt;

    //========================================================== generator
    logic [IW-1:0] flit_idx;
    logic [5:0]    tx_seq [0:1];      // sequence แยกต่อ VC
    logic          vc_sel;
    logic          gen_en, tx_fire, last_flit;

    assign gen_en    = (state == S_RUN);
    assign last_flit = (flit_idx == PKT_FLITS-1);

    // TX_EN=0 -> ไม่ยิงเลย ตัวนับ tx_flit_cnt/tx_stall_cnt จะค้างที่ 0
    // แต่ state machine กับฝั่ง rx ยังทำงานปกติ ยังรายงาน done/err ได้
    assign tx_tvalid = gen_en && TX_EN;
    assign tx_tdest  = DEST_ID;
    assign tx_tid    = vc_sel ? 2'b10 : 2'b01;
    assign tx_tdata  = {SRC_TAG, tx_seq[vc_sel]};
    assign tx_tlast  = last_flit;

    assign tx_fire = tx_tvalid &&
                     ((tx_tid[0] && tx_tready[0]) || (tx_tid[1] && tx_tready[1]));

    //========================================================== sink
    // รับเต็มอัตราเสมอ คอขวดจึงอยู่ที่ local output port ของ router เท่านั้น
    assign rx_tready = 2'b11;

    logic       rx_fire, rx_vc;
    logic [1:0] rx_src;
    logic [5:0] rx_seq;

    assign rx_fire = rx_tvalid;
    assign rx_vc   = rx_tid[1];        // tid 2'b10 = VC1
    assign rx_src  = rx_tdata[7:6];
    assign rx_seq  = rx_tdata[5:0];

    logic [5:0] exp_seq [0:3][0:1];    // [source][vc]
    logic       seeded  [0:3][0:1];
    logic       seq_bad;

    always_comb begin
        seq_bad = rx_fire && seeded[rx_src][rx_vc] &&
                  (rx_seq != exp_seq[rx_src][rx_vc]);
    end

    //========================================================== counters
    (* mark_debug = "true", dont_touch = "true" *) logic [31:0] tx_flit_cnt;
    (* mark_debug = "true", dont_touch = "true" *) logic [31:0] tx_stall_cnt;
    (* mark_debug = "true", dont_touch = "true" *) logic [31:0] rx_vc0_cnt;
    (* mark_debug = "true", dont_touch = "true" *) logic [31:0] rx_vc1_cnt;
    (* mark_debug = "true", dont_touch = "true" *) logic [31:0] rx_err_cnt;

    // ทำเป็นรีจิสเตอร์ ไม่ใช่ assign combinational เพื่อให้ trigger ของ ILA สะอาด
    (* mark_debug = "true", dont_touch = "true" *) logic test_done;

    //========================================================== liveness watchdog
    // 🔴 state machine เดินตาม win_cnt อย่างเดียว ไม่เคยถาม fabric สักคำ
    //    มันจึงไปถึง S_DONE แล้วชู done ขึ้นได้ ต่อให้ไม่มี flit ขยับเลยแม้แต่ตัวเดียว
    //    (รัน VC_MODE=2 ก่อนแก้ bug #3 ไฟเขียวติดบน fabric ที่ deadlock สนิทมาแล้ว)
    //    done จึงต้องมีหลักฐานว่า "ของเดินจริง" ไม่ใช่แค่ "นับครบ"
    //
    // sender  พิสูจน์ตัวเองด้วย tx_fire
    // sink    (TX_EN=0) ไม่เคยส่ง จึงพิสูจน์ด้วย rx_fire แทน
    //         ถ้าใช้ tx_fire กับ sink มันจะ false-fail ทุกครั้งโดยอัตโนมัติ
    localparam logic [GAP_W-1:0] STUCK_LIMIT = (1 << STUCK_LOG);

    logic [GAP_W-1:0] stuck_cnt;

    // max_gap = ช่องว่างที่ยาวที่สุดที่เคยเจอตลอด S_RUN
    //   นี่คือ "ตัววัด" ส่วน stuck_seen เป็นแค่ "คำตัดสิน"
    //   มีตัววัดแล้วถึงจะตั้งเกณฑ์จากข้อมูลจริงได้ ไม่ใช่เดา
    //   (เกณฑ์แรกตั้งไว้ 2^16 โดยเดาจาก traffic_gen ซึ่งเป็นคนละโมดูล คนละภาระงาน
    //    ผลคือ agent_01/agent_11 false-trip บนบอร์ดทั้งที่ fabric วิ่ง 97%)
    (* mark_debug = "true", dont_touch = "true" *) logic [GAP_W-1:0] max_gap;
    (* mark_debug = "true", dont_touch = "true" *) logic stuck_seen;

    logic live_fire;
    assign live_fire = TX_EN ? tx_fire : rx_fire;

    // หน้าต่างนับครบแล้วหรือยัง (แยกจากการ "ออกจาก S_RUN" เพราะต้องรอขอบแพ็กเกจ)
    logic win_full;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) test_done <= 1'b0;
        else        test_done <= (state == S_DONE);
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_WARMUP;
            warm_cnt     <= '0;
            win_cnt      <= '0;
            win_full     <= 1'b0;
            drain_cnt    <= '0;
            flit_idx     <= '0;
            vc_sel       <= (VC_MODE == 1);
            tx_seq[0]    <= '0;
            tx_seq[1]    <= '0;
            tx_flit_cnt  <= '0;
            tx_stall_cnt <= '0;
            stuck_cnt    <= '0;
            max_gap      <= '0;
            stuck_seen   <= 1'b0;
            rx_vc0_cnt   <= '0;
            rx_vc1_cnt   <= '0;
            rx_err_cnt   <= '0;
            for (int s = 0; s < 4; s++) begin
                for (int v = 0; v < 2; v++) begin
                    exp_seq[s][v] <= '0;
                    seeded[s][v]  <= 1'b0;
                end
            end
        end else begin

            //---- ตัวนับ เดินจนกว่าจะถึง S_DONE แล้วแช่ค่าไว้
            if (state != S_DONE) begin
                if (rx_fire) begin
                    seeded [rx_src][rx_vc] <= 1'b1;
                    exp_seq[rx_src][rx_vc] <= rx_seq + 1'b1;  // ครอบคลุมทั้งกรณี
                                                              // ปกติและ resync
                    if (seq_bad) rx_err_cnt <= rx_err_cnt + 1'b1;
                    if (rx_vc) rx_vc1_cnt <= rx_vc1_cnt + 1'b1;
                    else       rx_vc0_cnt <= rx_vc0_cnt + 1'b1;
                end

                if (tx_fire)                tx_flit_cnt  <= tx_flit_cnt  + 1'b1;
                if (tx_tvalid && !tx_fire)  tx_stall_cnt <= tx_stall_cnt + 1'b1;
            end

            //---- นาฬิกาจับตาย: เฝ้าเฉพาะช่วง S_RUN
            //     S_WARMUP ยังไม่มีอะไรวิ่ง / S_DRAIN ปิดขาส่งเองอยู่แล้ว
            //     ถ้าเฝ้าสองสถานะนั้นด้วยจะ false-fail ทันที
            if (state == S_RUN) begin
                if (live_fire)          stuck_cnt <= '0;
                else if (!(&stuck_cnt)) stuck_cnt <= stuck_cnt + 1'b1;

                // เก็บสถิติช่องว่างที่ยาวที่สุดไว้เสมอ ไม่ว่าจะถึงเกณฑ์หรือไม่
                if (stuck_cnt > max_gap)       max_gap    <= stuck_cnt;
                // เกินเกณฑ์ = ติดธงถาวร ต่อให้หลังจากนั้นจะกลับมาวิ่งได้ก็ตาม
                if (stuck_cnt >= STUCK_LIMIT)  stuck_seen <= 1'b1;
            end

            //---- ตัวชี้ของ generator
            if (tx_fire) begin
                tx_seq[vc_sel] <= tx_seq[vc_sel] + 1'b1;
                if (last_flit) begin
                    flit_idx <= '0;
                    if (VC_MODE == 2) vc_sel <= ~vc_sel;   // สลับ VC ทุก packet
                end else begin
                    flit_idx <= flit_idx + 1'b1;
                end
            end

            //---- ลำดับสถานะ
            case (state)
                S_WARMUP: begin                 // รอ async FIFO พ้น reset
                    warm_cnt <= warm_cnt + 1'b1;
                    if (&warm_cnt) state <= S_RUN;
                end
                S_RUN: begin
                    // 🔴 เดิม: พอ win_cnt เต็มก็ออกทันที ทำให้ tx_tvalid ตกกลางแพ็กเกจ
                    //    แพ็กเกจครึ่งท่อนค้างใน fabric แล้ว packet_arbiter ปลายทาง
                    //    ล็อกพอร์ตรอ tlast ที่ไม่มีวันมา -> พอร์ตนั้นตายถาวร
                    //    (วัดได้จริง: idx0 LOCAL ล็อกที่ NORTH ทั้งที่ NORTH ไม่มีของ
                    //     ส่วน EAST ที่มีของรออยู่ก็อดใช้ ทั้ง fabric เงียบ ~37k cycle)
                    //    ปลดล็อกฉุกเฉินใน packet_arbiter ช่วยไม่ได้ เพราะมันยิงเฉพาะ
                    //    ตอน has_transferred=0 เท่านั้น (เงื่อนไขที่ใส่ไว้แก้ bug #1)
                    //
                    // ใหม่: นับครบแล้วยังส่งต่อจนจบแพ็กเกจปัจจุบันก่อน ค่อยออก
                    //    ยืดหน้าต่างออกไปอย่างมาก PKT_FLITS flit ซึ่งเทียบกับ 2^24 แล้วไม่มีผล
                    if (!win_full) begin
                        win_cnt <= win_cnt + 1'b1;
                        if (&win_cnt) win_full <= 1'b1;
                    end
                    // sink ไม่มีแพ็กเกจค้าง ออกได้เลย
                    // ถ้า fabric ตายจริงจน tx_fire ไม่มาเลย stuck_seen จะพาออกเอง
                    // ไม่งั้นจะค้างใน S_RUN ตลอดกาลแล้วไม่มีใครได้รายงานผล
                    if (win_full && (!TX_EN || (tx_fire && last_flit) || stuck_seen))
                        state <= S_DRAIN;
                end
                S_DRAIN: begin                  // หยุดยิง รอ flit ที่ค้างในท่อ
                    drain_cnt <= drain_cnt + 1'b1;
                    if (&drain_cnt) state <= S_DONE;
                end
                S_DONE: ;                       // แช่ค่า รอ ILA อ่าน
                default: state <= S_WARMUP;
            endcase
        end
    end

    //========================================================== สรุปผลออก port
    // done = "จบ window แล้ว และมีของเดินจริงตลอดทาง"
    // ต่อตรงไป pass_group1/2 -> led[1]/led[2] ใน arty_stress_top
    // ดังนั้นไฟเขียวจะไม่ติดบน fabric ที่ตายอีกต่อไป
    // ILA ยังอ่าน test_done / state_dbg ดิบได้ตามเดิม ไว้แยกว่า
    // "ยังไม่จบ" กับ "จบแต่ตาย" ออกจากกัน ส่วน stuck_seen บอกว่า node ไหนตาย
    assign done = test_done && !stuck_seen;
    assign err  = (rx_err_cnt != 32'd0);

    //========================================================== ILA taps
    (* mark_debug = "true", dont_touch = "true" *) logic [1:0] state_dbg;
    (* mark_debug = "true", dont_touch = "true" *) logic [3:0] rx_tdest_dbg;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) state_dbg <= 2'b00;
        else        state_dbg <= state;
    end

    always_ff @(posedge clk) begin
        if (rx_tvalid) rx_tdest_dbg <= rx_tdest;   // ยืนยันว่า routing ถูกที่
    end

endmodule
