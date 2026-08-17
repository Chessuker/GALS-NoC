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

endmodule

