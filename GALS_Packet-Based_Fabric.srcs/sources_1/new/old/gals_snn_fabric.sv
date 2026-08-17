`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/17/2026 06:10:10 PM
// Design Name: 
// Module Name: gals_snn_fabric
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


module gals_snn_fabric #(
    parameter NUM_PRODUCERS = 4,
    parameter NUM_CONSUMERS = 4,
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 12
)(
    // ==========================================
    // ฝั่ง Producers (ทำงานที่ Clock ของใครของมัน)
    // ==========================================
    input  logic [NUM_PRODUCERS-1:0]                   clk_P,      
    input  logic [NUM_PRODUCERS-1:0]                   rst_P_n,    
    input  logic [NUM_PRODUCERS-1:0]                   p_valid,    
    input  logic [NUM_PRODUCERS-1:0][DATA_WIDTH-1:0]   p_data, 
    output logic [NUM_PRODUCERS-1:0]                   p_full,     

    // ==========================================
    // ฝั่ง Consumers (ทำงานร่วมกันที่ Clock ของระบบประสาทส่วนกลาง)
    // ==========================================
    input  logic                                       clk_C,
    input  logic                                       rst_C_n,
    input  logic [NUM_CONSUMERS-1:0]                   c_ready,
    output logic [NUM_CONSUMERS-1:0]                   c_valid,
    output logic [NUM_CONSUMERS-1:0][DATA_WIDTH-1:0]   c_data,
    
    // ตารางสับราง: Consumer ไหน อยากฟัง Producer ไหน
    input  logic [NUM_CONSUMERS-1:0][NUM_PRODUCERS-1:0] subscription_matrix 
);

    // ==========================================
    // 🔗 สายไฟเชื่อมต่อระหว่าง Layer 1 (FIFO) กับ Layer 2 (Crossbar)
    // ==========================================
    logic [NUM_PRODUCERS-1:0]                 fifo_empty;
    logic [NUM_PRODUCERS-1:0]                 fifo_rd_en; // คำสั่ง Pop จาก Crossbar
    logic [NUM_PRODUCERS-1:0][DATA_WIDTH-1:0] fifo_rdata;

    // ==========================================
    // Layer 1: The GALS CDC Bank (อาเรย์ของ Async FIFO)
    // ==========================================
    genvar i; 
    generate
        for (i = 0; i < NUM_PRODUCERS; i++) begin : gen_cdc_bank
            async_fifo #(
                .DATA_WIDTH(DATA_WIDTH),
                .ADDR_WIDTH(ADDR_WIDTH) 
            ) fifo_inst (
                // ขาเข้า: รับข้อมูลอิสระตามคล็อกของ P
                .wclk   (clk_P[i]),
                .wrst_n (rst_P_n[i]),
                .winc   (p_valid[i] & ~p_full[i]),
                .wdata  (p_data[i]),
                .wfull  (p_full[i]),
                
                // ขาออก: ซิงค์ทุกอย่างเข้าสู่คล็อกกลาง (clk_C)
                .rclk   (clk_C),
                .rrst_n (rst_C_n),
                .rinc   (fifo_rd_en[i]),   // 🔴 รอรับคำสั่ง Pop จาก Crossbar
                .rdata  (fifo_rdata[i]),   // 🔴 ส่งข้อมูลไปรอที่หน้าประตู Crossbar
                .rempty (fifo_empty[i])    // 🔴 บอกสถานะว่าคิวนี้ว่างไหม
            );
        end
    endgenerate

    // ==========================================
    // Layer 2: The Multicast Crossbar Switch
    // ==========================================
    gals_crossbar_mpmc #(
        .NUM_PRODUCERS(NUM_PRODUCERS),
        .NUM_CONSUMERS(NUM_CONSUMERS),
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) crossbar_inst (
        .clk     (clk_C),
        .rst_n   (rst_C_n),

        // 🔴 เชื่อมต่อกับคิว FIFO ฝั่งขาออก
        .p_empty (fifo_empty),
        .p_data  (fifo_rdata),
        .p_pop_en(fifo_rd_en),  // Crossbar เป็นคนตัดสินใจว่าจะ Pop คิวไหน

        // เชื่อมต่อกับ Consumer ภายนอก
        .c_ready (c_ready),
        .c_valid (c_valid),
        .c_data  (c_data),

        .subscription_matrix(subscription_matrix)
    );

endmodule