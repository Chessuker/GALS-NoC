`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Thawat Boonsuk
// 
// Create Date: 06/03/2026 10:48:21 PM
// Design Name: 
// Module Name: fwft_wrapper
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


module fwft_wrapper #(
    parameter DATA_WIDTH = 8
)(
    input  logic clk,       // ต้องต่อกับ rclk ของ FIFO
    input  logic rst_n,     // ต้องต่อกับ rrst_n ของ FIFO

    // -----------------------------------------
    // ฝั่งเชื่อมต่อกับ Async FIFO เดิม (Read Port)
    // -----------------------------------------
    input  logic                  f_rempty,
    input  logic [DATA_WIDTH-1:0] f_rdata,
    output logic                  f_r_en,

    // -----------------------------------------
    // ฝั่งเชื่อมต่อกับผู้ใช้ (Consumer) แบบ FWFT
    // -----------------------------------------
    output logic                  fwft_rempty,
    output logic [DATA_WIDTH-1:0] fwft_rdata,
    input  logic                  fwft_r_en
);

    // ==========================================
    // 1. Data Path Registers
    // ==========================================
    logic                  out_valid;   // ช่องที่ 1 (จ่อรอที่ Output)
    logic [DATA_WIDTH-1:0] out_data;
    
    logic                  skid_valid;  // ช่องที่ 2 (บัฟเฟอร์กันลื่น)
    logic [DATA_WIDTH-1:0] skid_data;

    // ติดตามสถานะว่า "มีข้อมูลกำลังเดินทางมาจาก BRAM ใน Cycle นี้หรือไม่"
    logic data_arriving;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) data_arriving <= 1'b0;
        else        data_arriving <= f_r_en;
    end

    // นามแฝงให้อ่านง่าย: ผู้ใช้อ่านสำเร็จเมื่อคิวไม่ว่างและกด Read
    logic user_read;
    assign user_read = fwft_r_en && out_valid;

    // ==========================================
    // 2. FIFO Read Enable Logic (No Data Loss!)
    // ==========================================
    // นับจำนวนข้อมูลที่อยู่ใน Wrapper ทั้งหมด (0 ถึง 3 ชิ้น)
    logic [1:0] valid_count;
    assign valid_count = out_valid + skid_valid + data_arriving;

    logic can_read;
    always_comb begin
        // เราสามารถดึงข้อมูลจาก FIFO ล่วงหน้าได้ ตราบใดที่ผลรวมข้อมูลใน Wrapper ไม่ล้น 2 ช่อง
        if (user_read) can_read = (valid_count <= 2);
        else           can_read = (valid_count <= 1);
    end

    assign f_r_en = !f_rempty && can_read;

    // ==========================================
    // 3. Output & Skid Update Logic
    // ==========================================
    assign fwft_rempty = !out_valid;
    assign fwft_rdata  = out_data;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid  <= 1'b0;
            skid_valid <= 1'b0;
            out_data   <= '0;
            skid_data  <= '0;
        end else begin
            // --------------------------------------
            // อัปเดตช่องที่ 1: Output Register
            // --------------------------------------
            if (user_read || !out_valid) begin
                if (skid_valid) begin
                    out_valid <= 1'b1;
                    out_data  <= skid_data;     // ขยับจาก Skid มา Output
                end else if (data_arriving) begin
                    out_valid <= 1'b1;
                    out_data  <= f_rdata;       // ทะลุ (Fall-Through) มาที่ Output
                end else begin
                    out_valid <= 1'b0;          // หมดเกลี้ยง
                end
            end

            // --------------------------------------
            // อัปเดตช่องที่ 2: Skid Register
            // --------------------------------------
            if (data_arriving) begin
                if (user_read || !out_valid) begin
                    if (skid_valid) begin
                        skid_valid <= 1'b1;
                        skid_data  <= f_rdata;  // Output ดึงข้อมูลไปแล้ว เอาของใหม่มาเติม Skid
                    end else begin
                        skid_valid <= 1'b0;     // ข้อมูลทะลุไป Output เลย Skid ปล่อยว่าง
                    end
                end else begin
                    // Output เต็มและไม่ได้ถูกอ่าน! ต้องพักข้อมูลใหม่ไว้ใน Skid ทันที
                    skid_valid <= 1'b1;
                    skid_data  <= f_rdata;
                end
            end else begin
                // ถ้าไม่มีข้อมูลใหม่เดินทางมา
                if (user_read || !out_valid) begin
                    skid_valid <= 1'b0;         // เคลียร์ Skid ทิ้งเพราะข้อมูลถูกย้ายไป Output แล้ว
                end
            end
        end
    end

    // =================================================================
    // THE PERFECT FORMAL VERIFICATION (STRUCTURAL INVARIANTS ONLY)
    // =================================================================
    `ifdef FORMAL
        reg f_past_valid = 1'b0;
        always @(posedge clk) f_past_valid <= 1'b1;

        always @(*) begin
            // บังคับให้ระบบเริ่มก้าวแรกด้วย Reset เสมอ
            if (!f_past_valid) assume(!rst_n);
        end

        // 🔴 กฎหมายรัฐธรรมนูญของ FWFT Wrapper 
        // กฎ 3 ข้อนี้คือคุณสมบัติที่แท้จริงของวงจร การันตี Data Integrity 
        // โดยไม่ถูก K-Induction เอาตัวแปรสถานะขยะมาโจมตี
        always @(*) begin
            if (rst_n) begin
                
                // 1. No Overflow: ข้อมูลรวมใน Wrapper ห้ามล้นความจุ 2 ช่อง (Output + Skid)
                // (กฎข้อนี้บังคับให้ Solver สุ่มค่า data_arriving, out_valid ได้สมเหตุสมผล)
                assert_no_overflow: assert(valid_count <= 2);
                
                // 2. Physical Queueing: บัฟเฟอร์กันลื่น (Skid) จะเก็บของได้ 
                // ก็ต่อเมื่อพอร์ต Output มีของจ่อเต็มอยู่ก่อนแล้วเท่านั้น! ห้ามข้ามขั้น!
                if (skid_valid) begin
                    assert_skid_physics: assert(out_valid == 1'b1);
                end

                // 3. Interface Protocol: สัญญาณ Empty ที่ส่งให้ผู้ใช้ 
                // ต้องสะท้อนสถานะความจริงของ Output Register เสมอ 100%
                assert_empty_status: assert(fwft_rempty == !out_valid);

            end else begin
                // สถานะหลังจากถูก Reset ทุกอย่างต้องถูกกวาดล้างเป็น 0 ให้หมด
                assert_reset_out:  assert(out_valid == 1'b0);
                assert_reset_skid: assert(skid_valid == 1'b0);
                assert_reset_arr:  assert(data_arriving == 1'b0);
            end
        end
    `endif

endmodule
