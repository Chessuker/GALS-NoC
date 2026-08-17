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
    parameter int         DRAIN_LOG  = 12
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
    input  logic [1:0] tx_tready
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
 
    assign tx_tvalid = gen_en;
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
    (* mark_debug = "true", dont_touch = "true" *) logic        test_done;
 
    // assign test_done = (state == S_DONE);
 
    (* mark_debug = "true", dont_touch = "true" *) logic test_done;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) test_done <= 1'b0;
        else        test_done <= (state == S_DONE);
    end
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_WARMUP;
            warm_cnt     <= '0;
            win_cnt      <= '0;
            drain_cnt    <= '0;
            flit_idx     <= '0;
            vc_sel       <= (VC_MODE == 1);
            tx_seq[0]    <= '0;
            tx_seq[1]    <= '0;
            tx_flit_cnt  <= '0;
            tx_stall_cnt <= '0;
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
            (* mark_debug = "true", dont_touch = "true" *) logic [31:0] state_cnt;
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
 
            (* mark_debug = "true", dont_touch = "true" *) logic [31:0] state_cnt;
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
                    win_cnt <= win_cnt + 1'b1;
                    if (&win_cnt) state <= S_DRAIN;
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
 
    //========================================================== ILA taps
    (* mark_debug = "true", dont_touch = "true" *) logic [1:0] state_dbg;
    (* mark_debug = "true", dont_touch = "true" *) logic [3:0] rx_tdest_dbg;
 
    assign state_dbg = state;
    always_ff @(posedge clk) begin
        if (rx_tvalid) rx_tdest_dbg <= rx_tdest;   // ยืนยันว่า routing ถูกที่
    end
 
endmodule
