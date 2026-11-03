`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Thawat Boonsuk
// 
// Create Date: 04/07/2026 09:21:46 PM
// Design Name: 
// Module Name: async_fifo
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


module async_fifo#(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
)(
    input logic wclk,
    input logic wrst_n,
    input logic w_en,
    input logic [DATA_WIDTH-1:0] wdata,
    output logic wfull,
    (* DONT_TOUCH = "TRUE" *) output logic [ADDR_WIDTH:0] w_level,
    
    input logic rclk,
    input logic rrst_n,
    input logic r_en,
    output logic [DATA_WIDTH-1:0] rdata,
    output logic rempty,

    output logic almost_full,
    input  logic [ADDR_WIDTH:0] prog_full_thresh, 

    output logic almost_empty,
    input  logic [ADDR_WIDTH:0] prog_empty_thresh,
    
    output logic ecc_single_err,
    output logic ecc_double_err
);
    
    logic [ADDR_WIDTH-1:0] waddr, raddr;
    logic [ADDR_WIDTH:0] wptr_g, rptr_g;
    logic [ADDR_WIDTH:0] wptr_g_sync, rptr_g_sync;

    // =================================================================
    // 🟢 แยก RAM: TDATA เข้า ECC, TLAST+TDEST เข้า RAM ธรรมดา
    // =================================================================
    `ifdef FORMAL
        dual_port_ram #(
            .DATA_WIDTH(DATA_WIDTH),
            .ADDR_WIDTH(ADDR_WIDTH)
        ) dp_ram (
            .wclk(wclk), .w_en(w_en && !wfull), .waddr(waddr), .wdata(wdata),
            .rclk(rclk), .r_en(r_en && !rempty), .raddr(raddr), .rdata(rdata)
        );
        assign ecc_single_err = 1'b0;
        assign ecc_double_err = 1'b0;

    `else
        logic [7:0] rdata_ecc;
        logic       raw_ecc_sbe, raw_ecc_dbe;
        logic       ecc_read_valid;

        // 1. RAM สำหรับ Payload (8 บิตล่าง) - มี ECC ป้องกัน Error
        dual_port_ram_ecc #(
            .DATA_WIDTH(8),
            .ADDR_WIDTH(ADDR_WIDTH)
        ) dp_ram_ecc_inst (
            .wclk(wclk),
            .w_en(w_en && !wfull),
            .waddr(waddr),
            .wdata(wdata[7:0]), // 🟢 ใส่แค่ 8 บิต
            .rclk(rclk),
            .r_en(r_en && !rempty),
            .raddr(raddr),
            .rdata(rdata_ecc),
            .ecc_single_err(raw_ecc_sbe),
            .ecc_double_err(raw_ecc_dbe)
        );

        // ธง ECC เป็นค่า combinational บน rdata ของ RAM ซึ่งค้างค่าล่าสุดไว้เสมอ
        // ก่อนจะมีการอ่านจริงครั้งแรก rdata ยังไม่ได้ init (X ใน sim / 0 บนบอร์ด)
        // ปล่อยดิบๆ ออกไปจะกลายเป็นสัญญาณเตือนหลอกตั้งแต่ยังไม่มีใครใช้งาน
        // จึงเปิดธงเฉพาะไซเคิลถัดจากการอ่านจริง = ธงนี้อธิบาย "คำที่เพิ่งอ่านออกมา"
        // ปลายทางเป็น latch แบบ sticky อยู่แล้ว พัลส์ไซเคิลเดียวจึงพอ
        always_ff @(posedge rclk or negedge rrst_n) begin
            if (!rrst_n) ecc_read_valid <= 1'b0;
            else         ecc_read_valid <= (r_en && !rempty);
        end

        assign ecc_single_err = raw_ecc_sbe && ecc_read_valid;
        assign ecc_double_err = raw_ecc_dbe && ecc_read_valid;

        // 2. RAM สำหรับ Control Bits (บิตที่ 8 ขึ้นไป) - ไม่มี ECC
        generate
            if (DATA_WIDTH > 8) begin : GEN_CTRL_RAM
                logic [(DATA_WIDTH-8)-1:0] rdata_ctrl;
                
                dual_port_ram #(
                    .DATA_WIDTH(DATA_WIDTH - 8),
                    .ADDR_WIDTH(ADDR_WIDTH)
                ) dp_ram_ctrl_inst (
                    .wclk(wclk),
                    .w_en(w_en && !wfull),
                    .waddr(waddr),
                    .wdata(wdata[DATA_WIDTH-1 : 8]), // 🟢 ใส่ 5 บิตที่เหลือ (TLAST, TDEST)
                    .rclk(rclk),
                    .r_en(r_en && !rempty),
                    .raddr(raddr),
                    .rdata(rdata_ctrl)
                );
                
                // 🟢 ประกอบร่าง 13 บิตกลับคืนมา
                assign rdata = {rdata_ctrl, rdata_ecc};
                
            end else begin : GEN_NO_CTRL
                assign rdata = rdata_ecc;
            end
        endgenerate
    `endif
    
    // =================================================================
    // FIFO Pointers & Gray Counters (เหมือนเดิม)
    // =================================================================
    gray_counter #(ADDR_WIDTH) w_cnt (
        .clk(wclk), .rst(!wrst_n), .en(w_en && !wfull), .ptr_g(wptr_g), .addr(waddr)
    );
    gray_counter #(ADDR_WIDTH) r_cnt (
        .clk(rclk), .rst(!rrst_n), .en(r_en && !rempty), .ptr_g(rptr_g), .addr(raddr)
    );
    sync_2stage #(ADDR_WIDTH+1) sync_w2r (
        .clk(rclk), .rst(!rrst_n), .d(wptr_g), .q(wptr_g_sync)
    );
    sync_2stage #(ADDR_WIDTH+1) sync_r2w (
        .clk(wclk), .rst(!wrst_n), .d(rptr_g), .q(rptr_g_sync)
    );

    assign rempty = (wptr_g_sync == rptr_g);
    assign wfull = (wptr_g == {~rptr_g_sync[ADDR_WIDTH], ~rptr_g_sync[ADDR_WIDTH-1], rptr_g_sync[ADDR_WIDTH-2:0]});

    // =================================================================
    // Level & Watermark Calculation (เหมือนเดิม)
    // =================================================================
    logic [ADDR_WIDTH:0] wptr_bin;
    logic [ADDR_WIDTH:0] rptr_bin_sync;

    always_comb begin
        wptr_bin[ADDR_WIDTH] = wptr_g[ADDR_WIDTH];
        for (int i = ADDR_WIDTH-1; i >= 0; i--) wptr_bin[i] = wptr_bin[i+1] ^ wptr_g[i];
    end

    always_comb begin
        rptr_bin_sync[ADDR_WIDTH] = rptr_g_sync[ADDR_WIDTH];
        for (int i = ADDR_WIDTH-1; i >= 0; i--) rptr_bin_sync[i] = rptr_bin_sync[i+1] ^ rptr_g_sync[i];
    end

    assign w_level = wptr_bin - rptr_bin_sync;
    assign almost_full = (w_level >= prog_full_thresh);

    logic [ADDR_WIDTH:0] rptr_bin;
    logic [ADDR_WIDTH:0] wptr_bin_sync;

    always_comb begin
        rptr_bin[ADDR_WIDTH] = rptr_g[ADDR_WIDTH];
        for (int i = ADDR_WIDTH-1; i >= 0; i--) rptr_bin[i] = rptr_bin[i+1] ^ rptr_g[i];
    end

    always_comb begin
        wptr_bin_sync[ADDR_WIDTH] = wptr_g_sync[ADDR_WIDTH];
        for (int i = ADDR_WIDTH-1; i >= 0; i--) wptr_bin_sync[i] = wptr_bin_sync[i+1] ^ wptr_g_sync[i];
    end

    logic [ADDR_WIDTH:0] r_level;
    assign r_level = wptr_bin_sync - rptr_bin;
    assign almost_empty = (r_level <= prog_empty_thresh);

    // =================================================================
    // FORMAL — เปิดเฉพาะตอน async_fifo เป็น top (formal/async_fifo.sby)
    // ตัวอื่นที่อ่านไฟล์นี้ (async_fifo_fwft.sby, gals_node_wrapper.sby) ไม่นิยาม
    // FORMAL_ASYNC_FIFO_TOP บล็อกนี้จึงไม่ไป assume ใส่สายที่มีคนขับอยู่แล้ว
    //
    // รันแบบ multiclock: wclk กับ rclk เป็นอินพุตอิสระ solver สลับขอบได้ทุกแบบ
    // (เร็ว/ช้ากว่ากัน ขอบชนกัน) ไม่ใช่ยุบสองนาฬิกาเป็นอันเดียวแบบสคริปต์เดิม
    // property ใช้ hierarchical reference ไปที่ bin / sync stage แรก / mem
    // จึงต้องอ่านด้วย slang (read_verilog ไม่รองรับ)
    // =================================================================
`ifdef FORMAL
`ifdef FORMAL_ASYNC_FIFO_TOP
    localparam int F_DEPTH = 1 << ADDR_WIDTH;

    function automatic logic [ADDR_WIDTH:0] f_g2b(input logic [ADDR_WIDTH:0] g);
        logic [ADDR_WIDTH:0] b;
        b[ADDR_WIDTH] = g[ADDR_WIDTH];
        for (int i = ADDR_WIDTH-1; i >= 0; i--) b[i] = b[i+1] ^ g[i];
        return b;
    endfunction

    // slang ยังไม่รองรับ $onehot0 — v มีบิตเดียวหรือศูนย์ <=> (v & (v-1)) == 0
    function automatic bit f_onehot0(input logic [ADDR_WIDTH:0] v);
        return (v & (v - 1'b1)) == '0;
    endfunction

    // ---------------------------------------------------------
    // สถานะรีเซ็ต
    // slang ไม่มี $initstate และไม่มี global clock ((* gclk *) ถูกมองเป็นสายค้าง
    // ทำให้ flop บนนั้นค้างค่าเริ่มตลอด — ลองแล้ว ได้ผลแบบ vacuous)
    // จึงจับขอบขาขึ้นของสายรีเซ็ตเองแทน: f_*_rel = ฝั่งนั้นถูกปล่อยรีเซ็ตแล้ว
    // ---------------------------------------------------------
    logic f_w_rel = 1'b0;
    logic f_r_rel = 1'b0;
    always @(posedge wrst_n) f_w_rel <= 1'b1;
    always @(posedge rrst_n) f_r_rel <= 1'b1;

    // ขอบเขตของ proof นี้ = cold start เท่านั้น: เริ่มจากรีเซ็ตทั้งสองฝั่ง ปล่อยคนละจังหวะได้
    // (reset_sync ต่อโดเมน) แต่ปล่อยแล้วไม่กดซ้ำ
    //
    // runtime reset ไม่อยู่ในขอบเขต: VIO soft reset ผ่าน reset_sync.srst ซึ่ง sync แยก
    // ในแต่ละโดเมน โดเมนจึงเข้ารีเซ็ตคนละขอบนาฬิกา ไม่ได้พร้อมกัน ถ้ามีของค้างในคิว
    // ตอนนั้น ฝั่งหนึ่งพอยน์เตอร์กลับเป็น 0 ขณะอีกฝั่งยังถือค่าเดิม = FIFO เสีย
    // ดีไซน์ไม่ได้กันเรื่องนี้ใน RTL — อาศัยข้อตกลงการใช้งานว่ากด soft reset ตอนไม่มีทราฟฟิก
    // (fault campaign รอ window จบก่อนรีเซ็ตทุกครั้ง, WALKTHROUGH 7.3)
    // ปุ่มรีเซ็ต (arst_n) assert ทุกโดเมนพร้อมกันแบบ async จึงไม่มีปัญหานี้ แต่ก็ไม่ได้
    // ถูกจำลองในนี้เช่นกัน
    always @(*) begin
        assume(wrst_n == f_w_rel);
        assume(rrst_n == f_r_rel);
    end

    // ---------------------------------------------------------
    // พอยน์เตอร์ในรูปเลขฐานสอง (ทุกผลต่างคิดแบบ mod 2^(ADDR_WIDTH+1)
    // ในสายกว้าง ADDR_WIDTH+1 ก่อนเทียบ ไม่ให้ขยายเป็น 32 บิตแล้วติดลบ)
    // ---------------------------------------------------------
    wire [ADDR_WIDTH:0] f_wbin   = wptr_bin;
    wire [ADDR_WIDTH:0] f_rbin   = rptr_bin;
    wire [ADDR_WIDTH:0] f_w2r_1  = f_g2b(sync_w2r.q1);    // wptr ระหว่างทาง stage 1
    wire [ADDR_WIDTH:0] f_w2r_2  = wptr_bin_sync;          // wptr ที่ฝั่งอ่านเห็น
    wire [ADDR_WIDTH:0] f_r2w_1  = f_g2b(sync_r2w.q1);
    wire [ADDR_WIDTH:0] f_r2w_2  = rptr_bin_sync;          // rptr ที่ฝั่งเขียนเห็น

    wire [ADDR_WIDTH:0] f_fill   = f_wbin  - f_rbin;       // จำนวนของจริงในคิว
    wire [ADDR_WIDTH:0] f_w2r_d1 = f_w2r_1 - f_rbin;
    wire [ADDR_WIDTH:0] f_w2r_d2 = f_w2r_2 - f_rbin;
    wire [ADDR_WIDTH:0] f_r2w_d1 = f_r2w_1 - f_r2w_2;
    wire [ADDR_WIDTH:0] f_r2w_dr = f_rbin  - f_r2w_2;
    wire [ADDR_WIDTH:0] f_r2w_dw = f_wbin  - f_r2w_2;

    wire f_wr = w_en && !wfull;
    wire f_rd = r_en && !rempty;

    // ค่า gray ก่อนขอบล่าสุดของแต่ละฝั่ง
    logic [ADDR_WIDTH:0] f_wptr_g_prev, f_rptr_g_prev;
    always @(posedge wclk or negedge wrst_n)
        if (!wrst_n) f_wptr_g_prev <= '0; else f_wptr_g_prev <= wptr_g;
    always @(posedge rclk or negedge rrst_n)
        if (!rrst_n) f_rptr_g_prev <= '0; else f_rptr_g_prev <= rptr_g;

    // ---------------------------------------------------------
    // flit หนึ่งตัวที่ solver เลือกเอง ถ้าตัวที่เลือกได้ออกมาถูกต้องและตรงลำดับ
    // ทุกตัวก็ถูก (เลือกตัวไหนก็ได้) f_k = พอยน์เตอร์เขียนเต็มความกว้างของมัน
    //
    // ตัวเลือก: prog_full_thresh[0] — อินพุตอิสระของ top ที่ใช้แค่คำนวณ almost_full
    // (ไม่มีสถานะภายใน) จึงไม่ไปบังคับอะไรในดีไซน์
    // ที่ไม่ใช้ $anyseq/$anyconst เพราะ slang ไม่รองรับ และ flop ที่ D=Q
    // ถูก opt แทนด้วย x ซึ่งแยกเป็นค่าอิสระทุกจุดที่ใช้ (ลองแล้ว ล้มหลอก)
    // ---------------------------------------------------------
    wire f_pick = prog_full_thresh[0];

    logic [ADDR_WIDTH:0]   f_k;
    logic [DATA_WIDTH-1:0] f_data;
    logic f_written = 1'b0;     // โดเมน wclk: flit ตัวนั้นถูกเขียนแล้ว
    logic f_read    = 1'b0;     // โดเมน rclk: ถูกอ่านออกไปแล้ว
    logic f_check   = 1'b0;     // rdata ตอนนี้คือ flit ตัวนั้น (จนกว่าจะอ่านตัวถัดไป)

    always @(posedge wclk)
        if (wrst_n && f_wr && !f_written && f_pick) begin
            f_written <= 1'b1;
            f_k       <= f_wbin;
            f_data    <= wdata;
        end

    always @(posedge rclk)
        if (rrst_n && f_rd) begin
            if (f_written && !f_read && f_rbin == f_k) begin
                f_read  <= 1'b1;
                f_check <= 1'b1;
            end else begin
                f_check <= 1'b0;
            end
        end

    always @(*) begin
        // ---- ความจุ: ไม่มี overflow ไม่มี underflow
        assert_fill_le_depth:    assert (f_fill <= F_DEPTH);
        if (f_fill == F_DEPTH)
            assert_full_when_full:   assert (wfull);
        if (f_fill == '0)
            assert_empty_when_empty: assert (rempty);

        // ---- level ที่ส่งออก (คำนวณจากพอยน์เตอร์ที่ sync มา) ไม่เกินความจุ
        assert_w_level_bound: assert (w_level <= F_DEPTH);
        assert_r_level_bound: assert (r_level <= F_DEPTH);

        // ---- พอยน์เตอร์ที่ข้ามโดเมนขยับทีละไม่เกินหนึ่งบิตต่อขอบ
        // (เงื่อนไขที่ทำให้ sync_2stage เก็บค่าที่ถูกต้องได้แม้จับตอนกำลังเปลี่ยน)
        assert_wptr_gray_step: assert (f_onehot0(wptr_g ^ f_wptr_g_prev));
        assert_rptr_gray_step: assert (f_onehot0(rptr_g ^ f_rptr_g_prev));

        // ---- ข้อมูลและลำดับ: flit ที่ติดตามออกมาค่าเดิม ตอนพอยน์เตอร์อ่าน = พอยน์เตอร์ตอนเขียน
        if (f_check)
            assert_tracked_data: assert (rdata == f_data);

        // ---- invariant (white-box) ให้ induction ปิดได้
        inv_wcnt_bin: assert (w_cnt.bin == f_wbin);
        inv_rcnt_bin: assert (r_cnt.bin == f_rbin);
        // ค่าที่กำลังข้ามไปฝั่งอ่านอยู่ระหว่าง rptr ถึง wptr เรียงตาม stage
        inv_w2r_order: assert (f_w2r_d2 <= f_w2r_d1 && f_w2r_d1 <= f_fill);
        // ค่าที่กำลังข้ามไปฝั่งเขียนตามหลัง rptr และฝั่งเขียนนำหน้ามันไม่เกินความจุ
        inv_r2w_order: assert (f_r2w_d1 <= f_r2w_dr && f_r2w_dr <= f_r2w_dw && f_r2w_dw <= F_DEPTH);
        inv_read_after_write: assert (!f_read  || f_written);
        inv_check_after_read: assert (!f_check || f_read);
        if (f_written && !f_read) begin
            inv_tracked_in_queue: assert ((f_k - f_rbin) < f_fill);
            inv_tracked_in_mem:   assert (dp_ram.mem[f_k[ADDR_WIDTH-1:0]] == f_data);
        end
        // ฝั่งที่ยังไม่เคยออกจากรีเซ็ต ทุกอย่างเป็นศูนย์
        if (!wrst_n)
            inv_w_in_reset: assert (f_wbin == '0 && f_rbin == '0 && f_r2w_1 == '0
                                    && f_r2w_2 == '0 && !f_written);
        if (!rrst_n)
            inv_r_in_reset: assert (f_rbin == '0 && f_w2r_1 == '0 && f_w2r_2 == '0
                                    && !f_read && !f_check);
    end

    // ---------------------------------------------------------
    // cover: คิวเต็มจริง, flit ที่ติดตามออกมา, พอยน์เตอร์อ่านวนรอบ
    // ---------------------------------------------------------
    logic f_rwrap = 1'b0;
    always @(posedge rclk)
        if (rrst_n && f_rd && f_rbin == '1) f_rwrap <= 1'b1;

    always @(*) begin
        cover_both_released: cover (f_w_rel && f_r_rel);
        cover_full:        cover (wfull && f_fill == F_DEPTH);
        cover_tracked_out: cover (f_check);
        cover_tracked_late: cover (f_check && f_k[ADDR_WIDTH]);
        cover_ptr_wrap:    cover (f_rwrap);
    end
`endif
`endif

endmodule

