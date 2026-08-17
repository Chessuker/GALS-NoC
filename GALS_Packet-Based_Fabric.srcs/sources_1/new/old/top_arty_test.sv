`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/08/2026 06:08:23 PM
// Design Name: 
// Module Name: top_arty_test
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


module top_arty_test (
    input  logic       CLK100MHZ, // Pin E3 (Onboard Oscillator)
    input  logic       btn_rst,   // Pin button 0 (Active High Hardware Reset)
    input  logic       sw_ready,  // Pin slide switch 0 (Manual Consumer Ready control)
    output logic [3:0] led        // Pins LED 3-0 for hardware status checks
);

    // =================================================================
    // 1. CLOCK TREES GENERATION (Clocking Wizard Instance)
    // =================================================================
    logic clk_P0, clk_P1, clk_P2, clk_B;
    logic clk_locked;

    // หมายเหตุ: คุณต้องสร้าง IP Core ชื่อ 'clk_wiz_0' ใน IP Catalog 
    // และตั้งค่าพอร์ต Output ให้ได้ความถี่ตามนี้
    clk_wiz_0 clk_gen (
        .clk_in1  (CLK100MHZ),  // Onboard 100 MHz
        .reset    (btn_rst),    // Active High reset จากปุ่มกด
        .clk_out1 (clk_P0),     // 125 MHz  (Producer 0)
        .clk_out2 (clk_P1),     // 100 MHz  (Producer 1)
        .clk_out3 (clk_P2),     // 83.33MHz (Producer 2)
        .clk_out4 (clk_B),      // 166.67MHz(Consumer)
        .locked   (clk_locked)  // จะเป็น 1 เมื่อคล็อกทุกต้นเสถียรแล้ว
    );

    // =================================================================
    // 2. RESET BRIDGES (Asynchronous Assert, Synchronous Deassert)
    // =================================================================
    // ป้องกันปัญหา Metastability ของสัญญาณ Reset ข้ามโดเมน
    logic rst_P0_n, rst_P1_n, rst_P2_n, rst_B_n;
    
    // สร้าง Reset Bridge แยกอิสระตามโดเมนคล็อก
    always_ff @(posedge clk_P0 or negedge clk_locked) begin
        if (!clk_locked) rst_P0_n <= 1'b0;
        else             rst_P0_n <= 1'b1;
    end
    
    always_ff @(posedge clk_P1 or negedge clk_locked) begin
        if (!clk_locked) rst_P1_n <= 1'b0;
        else             rst_P1_n <= 1'b1;
    end
    
    always_ff @(posedge clk_P2 or negedge clk_locked) begin
        if (!clk_locked) rst_P2_n <= 1'b0;
        else             rst_P2_n <= 1'b1;
    end

    always_ff @(posedge clk_B or negedge clk_locked) begin
        if (!clk_locked) rst_B_n  <= 1'b0;
        else             rst_B_n  <= 1'b1;
    end


    // =================================================================
    // 3. HARDWARE TRAFFIC GENERATORS (Counters acting as Producers)
    // =================================================================
    // สัญญาณเชื่อมต่อเข้า DUT
    logic p0_valid, p1_valid, p2_valid;
    logic [7:0] p0_data, p1_data, p2_data;
    logic p0_full, p1_full, p2_full;

    // --- Producer 0 (125 MHz): ส่งทราฟฟิกข้อมูลอย่างต่อเนื่องถ้า FIFO ไม่เต็ม ---
    logic [5:0] p0_counter;
    always_ff @(posedge clk_P0 or negedge rst_P0_n) begin
        if (!rst_P0_n) begin
            p0_valid   <= 1'b0;
            p0_data    <= 8'h00;
            p0_counter <= 6'd0;
        end else begin
            if (!p0_full) begin
                p0_valid   <= 1'b1;
                p0_data    <= {2'b00, p0_counter}; // Bits[7:6] แปะป้าย ID = 0
                p0_counter <= p0_counter + 1'b1;
            end else begin
                p0_valid   <= 1'b0; // FIFO เต็ม ให้หยุดดึงสัญญาณ valid ลง
            end
        end
    end

    // --- Producer 1 (100 MHz) ---
    logic [5:0] p1_counter;
    always_ff @(posedge clk_P1 or negedge rst_P1_n) begin
        if (!rst_P1_n) begin
            p1_valid   <= 1'b0;
            p1_data    <= 8'h00;
            p1_counter <= 6'd0;
        end else begin
            if (!p1_full) begin
                p1_valid   <= 1'b1;
                p1_data    <= {2'b01, p1_counter}; // Bits[7:6] แปะป้าย ID = 1
                p1_counter <= p1_counter + 1'b1;
            end else begin
                p1_valid   <= 1'b0;
            end
        end
    end

    // --- Producer 2 (83.33 MHz) ---
    logic [5:0] p2_counter;
    always_ff @(posedge clk_P2 or negedge rst_P2_n) begin
        if (!rst_P2_n) begin
            p2_valid   <= 1'b0;
            p2_data    <= 8'h00;
            p2_counter <= 6'd0;
        end else begin
            if (!p2_full) begin
                p2_valid   <= 1'b1;
                p2_data    <= {2'b10, p2_counter}; // Bits[7:6] แปะป้าย ID = 2
                p2_counter <= p2_counter + 1'b1;
            end else begin
                p2_valid   <= 1'b0;
            end
        end
    end


    // =================================================================
    // 4. DEVICE UNDER TEST (DUT INSTANTIATION)
    // =================================================================
    logic consumer_valid;
    logic [7:0] consumer_data;
    logic [2:0] p_ecc_single_err;
    logic [2:0] p_ecc_double_err;

    gals_top_mpmc dut (
        .clk_P0(clk_P0), .rst_P0_n(rst_P0_n), .p0_valid(p0_valid), .p0_data(p0_data), .p0_full(p0_full),
        .clk_P1(clk_P1), .rst_P1_n(rst_P1_n), .p1_valid(p1_valid), .p1_data(p1_data), .p1_full(p1_full),
        .clk_P2(clk_P2), .rst_P2_n(rst_P2_n), .p2_valid(p2_valid), .p2_data(p2_data), .p2_full(p2_full),
        .clk_B(clk_B),   .rst_B_n(rst_B_n),   
        .consumer_ready(sw_ready), // ใช้ Slide Switch คุม Backpressure แบบแมนนวลได้จากภายนอก
        .consumer_valid(consumer_valid), 
        .consumer_data(consumer_data),
        .p_ecc_single_err(p_ecc_single_err), 
        .p_ecc_double_err(p_ecc_double_err)
    );


    // =================================================================
    // 5. STATUS MAPPING TO ONBOARD LEDs (Visual Sanity Check)
    // =================================================================
    always_comb begin
        led[0] = p0_full; // ไฟดวงที่ 0 ติดเมื่อ FIFO P0 เต็ม
        led[1] = p1_full; // ไฟดวงที่ 1 ติดเมื่อ FIFO P1 เต็ม
        led[2] = p2_full; // ไฟดวงที่ 2 ติดเมื่อ FIFO P2 เต็ม
        // ไฟดวงที่ 3 ติดเมื่อเกิดข้อผิดพลาดของข้อมูลข้ามโดเมนหรือตัวแครชระบบ
        led[3] = (|p_ecc_single_err) || (|p_ecc_double_err) || !clk_locked;
    end


    // =================================================================
    // 6. INTEGRATED LOGIC ANALYZER (ILA Core Template)
    // =================================================================
    // บังคับรันกล้องวงจรปิดด้วยคล็อกฝั่งผู้รับ (Fast Consumer @ 166MHz)
    // เพื่อให้เก็บรายละเอียดตอน Arbiter สลับสัญญาณได้ครบถ้วน
    ila_0 hardware_analyzer (
        .clk(clk_B),
        .probe0(consumer_valid),    // 1 bit
        .probe1(sw_ready),          // 1 bit
        .probe2(consumer_data),     // 8 bits
        .probe3(p0_full),           // 1 bit
        .probe4(p1_full),           // 1 bit
        .probe5(p2_full),           // 1 bit
        .probe6(p_ecc_single_err),  // 3 bits
        .probe7(p_ecc_double_err)   // 3 bits
    );

endmodule
