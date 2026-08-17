`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/04/2026 05:11:30 PM
// Design Name: 
// Module Name: sync_fifo
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


module sync_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH = 16
)(
    input  logic clk,
    input  logic rst_n,
    
    // ฝั่งเขียน (Write)
    input  logic w_en,
    input  logic [DATA_WIDTH-1:0] w_data,
    
    // ฝั่งอ่าน (Read)
    input  logic r_en,
    output logic [DATA_WIDTH-1:0] r_data,
    
    // สถานะ
    output logic full,
    output logic empty
);

    localparam ADDR_W = $clog2(DEPTH);
    
    // หน่วยความจำ (Distributed RAM สำหรับความลึกน้อยๆ)
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    
    // พอยน์เตอร์
    logic [ADDR_W:0] w_ptr, r_ptr;
    
    logic is_empty;
    assign is_empty = (w_ptr == r_ptr);
    assign full     = (w_ptr[ADDR_W] != r_ptr[ADDR_W]) && (w_ptr[ADDR_W-1:0] == r_ptr[ADDR_W-1:0]);

    // 🟢 FWFT (First-Word Fall-Through) Logic:
    // ดึงข้อมูลออกมาโชว์ที่ r_data ทันทีที่ไม่มีสถานะ empty ไม่ต้องรอ r_en
    assign r_data = mem[r_ptr[ADDR_W-1:0]];
    assign empty  = is_empty;

    // ==============================================================
    // 1. บล็อกสำหรับ "เขียนหน่วยความจำ" (ห้ามมี rst_n ในวงเล็บเด็ดขาด!)
    // ==============================================================
    always_ff @(posedge clk) begin
        if (w_en && !full) begin
            mem[w_ptr[ADDR_W-1:0]] <= w_data;
        end
    end

    // ==============================================================
    // 2. บล็อกสำหรับ "จัดการ Pointer" (ใส่ rst_n ได้ตามปกติ)
    // ==============================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_ptr <= '0;
            r_ptr <= '0;
        end else begin
            // ลอจิกการเพิ่มค่า w_ptr
            if (w_en && !full) begin
                w_ptr <= w_ptr + 1'b1;
            end
            
            // ลอจิกการเพิ่มค่า r_ptr
            if (r_en && !is_empty) begin
                r_ptr <= r_ptr + 1'b1;
            end
        end
    end

endmodule

