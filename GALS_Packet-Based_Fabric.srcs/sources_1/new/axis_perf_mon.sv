`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/02/2026 06:46:08 PM
// Design Name: 
// Module Name: axis_perf_mon
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


module axis_perf_mon (
    input logic clk,
    input logic rst_n,

    // สายไฟ AXI4-Stream ที่ต้องการดักฟัง
    input logic valid,
    input logic ready,
    input logic last,

    // สัญญาณควบคุม (จาก Testbench หรือ CPU)
    input logic clear, // รีเซ็ตตัวนับ
    input logic en,    // เปิดการนับ

    // Output สถิติ (Performance Counters)
    output logic [31:0] flit_cnt,   // จำนวน Flit ที่ส่งสำเร็จ
    output logic [31:0] pkt_cnt,    // จำนวน Packet ที่ส่งจบ
    output logic [31:0] stall_cnt,  // จำนวน Clock ที่รถติด (Valid=1 แต่ Ready=0)
    output logic [31:0] active_cnt  // จำนวน Clock ที่ระบบทำงาน (ใช้หา % Utilization)
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flit_cnt   <= '0;
            pkt_cnt    <= '0;
            stall_cnt  <= '0;
            active_cnt <= '0;
        end else if (clear) begin
            flit_cnt   <= '0;
            pkt_cnt    <= '0;
            stall_cnt  <= '0;
            active_cnt <= '0;
        end else if (en) begin
            // 1. นับเวลาทำงานทั้งหมด
            active_cnt <= active_cnt + 1'b1;

            // 2. นับการส่งข้อมูลสำเร็จ (Handshake)
            if (valid && ready) begin
                flit_cnt <= flit_cnt + 1'b1;
                if (last) pkt_cnt <= pkt_cnt + 1'b1;
            end

            // 3. นับจังหวะรถติด (Backpressure)
            if (valid && !ready) begin
                stall_cnt <= stall_cnt + 1'b1;
            end
        end
    end

endmodule

