`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/09/2026 04:38:52 PM
// Design Name: 
// Module Name: pulse_sync
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


module pulse_sync (
    input  logic clk_a, rst_a, pulse_a, // โดเมนต้นทาง (UART 100MHz)
    input  logic clk_b, rst_b,          // โดเมนปลายทาง (P0 หรือ P2)
    output logic pulse_b                // สัญญาณ valid ฝั่งปลายทาง
);
    logic toggle_a;
    // ฝั่ง A: แปลง Pulse เป็นการสลับค่า Toggle (0->1 หรือ 1->0)
    always_ff @(posedge clk_a or posedge rst_a) begin
        if (rst_a) toggle_a <= 0;
        else if (pulse_a) toggle_a <= ~toggle_a;
    end
    
    // ฝั่ง B: ใช้ 2-Stage Sync ดึงค่า Toggle ข้ามมา แล้วทำ Edge Detection
    (* ASYNC_REG = "TRUE" *) logic [2:0] sync_b;
    always_ff @(posedge clk_b or posedge rst_b) begin
        if (rst_b) sync_b <= 0;
        else sync_b <= {sync_b[1:0], toggle_a}; // Shift register
    end
    
    // ดักจับการเปลี่ยนแปลง (Edge) เพื่อสร้าง Pulse 1 คล็อกในฝั่ง B
    assign pulse_b = sync_b[2] ^ sync_b[1]; 
endmodule
