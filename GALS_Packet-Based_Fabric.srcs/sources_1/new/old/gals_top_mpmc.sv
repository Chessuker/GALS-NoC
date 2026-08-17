`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/03/2026 11:27:56 PM
// Design Name: 
// Module Name: gals_top_mpmc
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


module gals_top_mpmc #(
    parameter NUM_PRODUCERS = 3,
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 11
)(
    // =======================================================
    // 1. Producer Domains (อิสระทาง Clock 100%)
    // =======================================================
    // Producer 0
    input  logic                  clk_P0, 
    input  logic                  rst_P0_n,
    input  logic                  p0_valid,
    input  logic [DATA_WIDTH-1:0] p0_data,
    output logic                  p0_full,
    output logic                  p0_almost_full,

    // Producer 1
    input  logic                  clk_P1, 
    input  logic                  rst_P1_n,
    input  logic                  p1_valid,
    input  logic [DATA_WIDTH-1:0] p1_data,
    output logic                  p1_full,
    output logic                  p1_almost_full,

    // Producer 2
    input  logic                  clk_P2, 
    input  logic                  rst_P2_n,
    input  logic                  p2_valid,
    input  logic [DATA_WIDTH-1:0] p2_data,
    output logic                  p2_full,
    output logic                  p2_almost_full,

    // =======================================================
    // 2. Consumer & Arbiter Domain (clk_B)
    // =======================================================
    input  logic                  clk_B,
    input  logic                  rst_B_n,
    
    input  logic                  consumer_ready, // Consumer พร้อมรับข้อมูลไหม
    output logic                  consumer_valid, // มีข้อมูลส่งให้ Consumer
    output logic [DATA_WIDTH-1:0] consumer_data,   // ข้อมูลที่จะส่ง
    
    output logic [2:0] p_ecc_single_err,
    output logic [2:0] p_ecc_double_err
);

    // สายไฟเชื่อมระหว่าง FIFO ฝั่งอ่าน กับ Arbiter
    logic [NUM_PRODUCERS-1:0]                  fifo_rempty;
    logic [NUM_PRODUCERS-1:0]                  fifo_r_en;
    logic [NUM_PRODUCERS-1:0][DATA_WIDTH-1:0]  fifo_rdata;

    // =======================================================
    // กล่องที่ 1-3: Async FIFO + FWFT ประจำตัว Producer
    // =======================================================
    // (หมายเหตุ: สมมติว่าคุณเอาโค้ด async_fifo และ fwft_wrapper มัดรวมกัน
    // เป็นโมดูลชื่อ async_fifo_fwft ไว้แล้ว)

    async_fifo_fwft #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) fifo_p0 (
        .wclk(clk_P0), .wrst_n(rst_P0_n), .w_en(p0_valid), .wdata(p0_data), .wfull(p0_full),
        .almost_full(p0_almost_full), .prog_full_thresh(12'd2000),
        .rclk(clk_B),  .rrst_n(rst_B_n),  .r_en(fifo_r_en[0]), .rdata(fifo_rdata[0]), .rempty(fifo_rempty[0]),
        .ecc_single_err (p_ecc_single_err[0]), .ecc_double_err (p_ecc_double_err[0])
    );

    async_fifo_fwft #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) fifo_p1 (
        .wclk(clk_P1), .wrst_n(rst_P1_n), .w_en(p1_valid), .wdata(p1_data), .wfull(p1_full),
        .almost_full(p1_almost_full), .prog_full_thresh(12'd2000),
        .rclk(clk_B),  .rrst_n(rst_B_n),  .r_en(fifo_r_en[1]), .rdata(fifo_rdata[1]), .rempty(fifo_rempty[1]),
        .ecc_single_err (p_ecc_single_err[1]), .ecc_double_err (p_ecc_double_err[1])
    );

    async_fifo_fwft #(.DATA_WIDTH(DATA_WIDTH), .ADDR_WIDTH(ADDR_WIDTH)) fifo_p2 (
        .wclk(clk_P2), .wrst_n(rst_P2_n), .w_en(p2_valid), .wdata(p2_data), .wfull(p2_full),
        .almost_full(p2_almost_full), .prog_full_thresh(12'd2000),
        .rclk(clk_B),  .rrst_n(rst_B_n),  .r_en(fifo_r_en[2]), .rdata(fifo_rdata[2]), .rempty(fifo_rempty[2]),
        .ecc_single_err (p_ecc_single_err[2]), .ecc_double_err (p_ecc_double_err[2])
    );

    // =======================================================
    // กล่องที่ 4: 1-Cycle Round-Robin Arbiter (ทำหน้าที่เป็นจราจรฝั่งออก)
    // =======================================================
    // ความเจ๋งคือ: เราเอา Arbiter ที่เคยเขียนไว้ฝั่ง Write มากลับด้านใช้กับฝั่ง Read ได้เป๊ะๆ!
    
    hw_queue_descriptor #(
        .NUM_PRODUCERS(NUM_PRODUCERS),
        .DATA_WIDTH(DATA_WIDTH)
    ) u_arbiter (
        .clk(clk_B),
        .rst_n(rst_B_n),
        
        // 1. คำขอ (Request) คือการที่คิวบอกว่า "ฉันไม่ว่างนะ มีข้อมูลมาแล้ว!"
        .req(~fifo_rempty),
        
        // 2. การให้สิทธิ์ (Grant) คือการสั่ง r_en ให้คิวที่ชนะเพื่อดึงข้อมูลออก
        .grant(fifo_r_en),
        
        // 3. ข้อมูลที่รออยู่ (เพราะเราใช้ FWFT ข้อมูลจึงมารอที่พอร์ต rdata แล้ว)
        .prod_data(fifo_rdata),
        
        // 4. เงื่อนไขการหยุด: ถ้า Consumer ปลายทางไม่ ready ถือว่าท่อเต็ม (wfull)
        .fifo_wfull(!consumer_ready),
        
        // 5. สัญญาณส่งออกหา Consumer
        .fifo_w_en(consumer_valid),
        .fifo_wdata(consumer_data)
    );

endmodule