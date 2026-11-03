`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/03/2026 11:01:09 PM
// Design Name: 
// Module Name: async_fifo_fwft
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


module async_fifo_fwft #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
)(
    // ==========================================
    // พอร์ตฝั่งเขียน (Write Domain)
    // ==========================================
    input  logic                  wclk,
    input  logic                  wrst_n,
    input  logic                  w_en,
    input  logic [DATA_WIDTH-1:0] wdata,
    output logic                  wfull,
    
    output logic                  almost_full,
    input  logic [ADDR_WIDTH:0]   prog_full_thresh,

    // ==========================================
    // พอร์ตฝั่งอ่าน (Read Domain - FWFT)
    // ==========================================
    input  logic                  rclk,
    input  logic                  rrst_n,
    input  logic                  r_en,
    output logic [DATA_WIDTH-1:0] rdata,
    output logic                  rempty,
    
    output logic                  ecc_single_err,
    output logic                  ecc_double_err
);

    // สายไฟเชื่อมต่อตรงกลางระหว่าง Core FIFO กับ Wrapper
    logic                  internal_rempty;
    logic [DATA_WIDTH-1:0] internal_rdata;
    logic                  internal_r_en;

    // ==========================================
    // กล่องที่ 1: Core Async FIFO (ตัวหลักที่มี ECC)
    // ==========================================
    async_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) core_fifo (
        // ฝั่งเขียน
        .wclk(wclk),
        .wrst_n(wrst_n),
        .w_en(w_en),
        .wdata(wdata),
        .wfull(wfull),
        
        // สัญญาณ Watermarks และ ECC (ปล่อยลอยไว้ก่อนใน Top นี้)
        .w_level(),          
        .almost_full(almost_full),      
        .prog_full_thresh(prog_full_thresh),
        .almost_empty(),     
        .prog_empty_thresh('0),
        .ecc_single_err(ecc_single_err),   
        .ecc_double_err(ecc_double_err),
        
        // ฝั่งอ่าน (ต่อสายไฟภายในไปเข้า Wrapper)
        .rclk(rclk),
        .rrst_n(rrst_n),
        .r_en(internal_r_en),
        .rdata(internal_rdata),
        .rempty(internal_rempty)
    );

    // ==========================================
    // กล่องที่ 2: FWFT Wrapper (บัฟเฟอร์ทำ FWFT)
    // ==========================================
    fwft_wrapper #(
        .DATA_WIDTH(DATA_WIDTH)
    ) fwft_inst (
        .clk(rclk),           
        .rst_n(rrst_n),
        
        // เชื่อมกับ Core FIFO ด้านบน
        .f_rempty(internal_rempty),
        .f_rdata(internal_rdata),
        .f_r_en(internal_r_en),
        
        // พอร์ตออกไปหาผู้ใช้จริง (แมปเข้าชื่อพอร์ตหลักของไฟล์นี้)
        .fwft_rempty(rempty),
        .fwft_rdata(rdata),
        .fwft_r_en(r_en)
    );

    // =================================================================
    // FORMAL — เปิดเฉพาะตอน async_fifo_fwft เป็น top (formal/async_fifo_fwft.sby)
    // ต้องอ่านคู่กับ FORMAL_ASYNC_FIFO_TOP: core_fifo พิสูจน์ตัวเองจนถึงพอร์ตอ่านของมัน
    // บล็อกนี้ตาม flit ตัวเดียวกับที่ core_fifo ติดตาม (f_k, f_data) ต่อผ่าน
    // fwft_wrapper ไปจนถึงมือผู้ใช้ — ข้อมูลและลำดับจากปลายถึงปลาย สองนาฬิกาจริง
    // =================================================================
`ifdef FORMAL
`ifdef FORMAL_ASYNC_FIFO_FWFT_TOP
    wire f_user_rd = r_en && !rempty;

    // จำนวน flit ที่ผู้ใช้อ่านไปแล้ว นับแบบเดียวกับพอยน์เตอร์ (mod 2^(ADDR_WIDTH+1))
    logic [ADDR_WIDTH:0] f_ucnt;
    always @(posedge rclk or negedge rrst_n)
        if (!rrst_n) f_ucnt <= '0;
        else if (f_user_rd) f_ucnt <= f_ucnt + 1'b1;

    // ดึงออกจาก core แล้วแต่ผู้ใช้ยังไม่ได้อ่าน: out + skid + ที่กำลังมาจาก RAM
    wire [1:0]            f_held = fwft_inst.valid_count;
    // ตำแหน่งของ flit ที่ติดตาม นับจากหัวคิวฝั่งผู้ใช้
    wire [ADDR_WIDTH:0]   f_off  = core_fifo.f_k - f_ucnt;
    logic f_udone = 1'b0;   // ผู้ใช้อ่าน flit ที่ติดตามไปแล้ว
    wire                  f_hit  = core_fifo.f_written && !f_udone && f_off == '0;

    always @(posedge rclk)
        if (rrst_n && f_user_rd && f_hit) f_udone <= 1'b1;

    always @(*) begin
        // ---- ข้อมูลและลำดับถึงมือผู้ใช้: ตอนที่ผู้ใช้อ่านครั้งที่ f_k คือ flit ตัวนั้น ค่าเดิม
        if (f_user_rd && f_hit)
            assert_user_tracked_data: assert (rdata == core_fifo.f_data);

        // ---- invariant ให้ induction ปิดได้
        // core อ่านไปกี่ตัว = ผู้ใช้อ่านไปกี่ตัว + ที่ค้างใน wrapper
        inv_ucnt: assert (core_fifo.f_rbin - f_ucnt == f_held);
        inv_udone_after_fetch: assert (!f_udone || core_fifo.f_read);
        if (core_fifo.f_written && !core_fifo.f_read)
            inv_trk_not_fetched: assert (f_off >= f_held);
        if (core_fifo.f_read && !f_udone) begin
            inv_trk_in_wrapper: assert (f_off < f_held);
            // ลำดับใน wrapper: out (เก่าสุด) -> skid -> ที่กำลังมาจาก RAM
            if (f_off == '0) begin
                if (fwft_inst.out_valid)
                    inv_trk_at_out: assert (fwft_inst.out_data == core_fifo.f_data);
                else
                    inv_trk_arriving0: assert (fwft_inst.data_arriving
                                               && internal_rdata == core_fifo.f_data);
            end else begin
                if (fwft_inst.skid_valid)
                    inv_trk_at_skid: assert (fwft_inst.skid_data == core_fifo.f_data);
                else
                    inv_trk_arriving1: assert (fwft_inst.data_arriving
                                               && internal_rdata == core_fifo.f_data);
            end
        end
        if (!rrst_n)
            inv_u_in_reset: assert (f_ucnt == '0 && !f_udone);
    end

    always @(*) begin
        cover_user_tracked:      cover (f_user_rd && f_hit);
        cover_user_tracked_late: cover (f_user_rd && f_hit && core_fifo.f_k[ADDR_WIDTH]);
        cover_skid_used:         cover (fwft_inst.skid_valid && !r_en);
    end
`endif
`endif

endmodule

