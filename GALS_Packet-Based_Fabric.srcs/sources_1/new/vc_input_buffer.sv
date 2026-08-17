`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/03/2026 10:32:33 PM
// Design Name: 
// Module Name: vc_input_buffer
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


module vc_input_buffer #(
    parameter DATA_W = 8,
    parameter CORD_W = 2,
    parameter NUM_VCS = 2,    // จำนวน Virtual Channels (เช่น 2 เลน)
    parameter DEPTH = 16      // ความลึกของ FIFO แต่ละ VC
)(
    input  logic clk,
    input  logic rst_n,

    // ---------------------------------------------------------
    // ฝั่งรับเข้า (RX from Network/Host) - สายไฟเส้นเดียว
    // ---------------------------------------------------------
    input  logic              s_valid,
    input  logic              s_tlast,
    input  logic [3:0]        s_tdest,
    input  logic [DATA_W-1:0] s_tdata,
    input  logic [NUM_VCS-1:0]s_tid,   // VC ID แบบ One-hot (01 = VC0, 10 = VC1)
    output logic [NUM_VCS-1:0]s_ready, // แจ้งกลับไปว่า VC ไหนพร้อมรับบ้าง (Per-VC Backpressure)

    // ---------------------------------------------------------
    // ฝั่งส่งออก (TX to Router Switch) - แยกสายไฟตามจำนวน VC
    // ---------------------------------------------------------
    output logic              m_valid [NUM_VCS],
    output logic              m_tlast [NUM_VCS],
    output logic [3:0]        m_tdest [NUM_VCS],
    output logic [DATA_W-1:0] m_tdata [NUM_VCS],
    input  logic              m_ready [NUM_VCS]
);

    // สร้าง FIFO แยกสำหรับแต่ละ Virtual Channel
    generate
        for (genvar v = 0; v < NUM_VCS; v++) begin : gen_vc_fifo
            
            // สัญญาณ write enable สำหรับ FIFO ตัวนี้ (เมื่อ Valid มา และ TID ชี้มาที่ VC นี้)
            logic fifo_we;
            assign fifo_we = s_valid && s_tid[v];

            // ข้อมูลที่รวมกันเป็นก้อนเดียวเพื่อเก็บลง FIFO (TLAST + TDEST + TDATA)
            localparam PACK_W = 1 + 4 + DATA_W;
            logic [PACK_W-1:0] wdata, rdata;
            
            assign wdata = {s_tlast, s_tdest, s_tdata};
            
            logic fifo_full, fifo_empty;
            
            // แจ้งสถานะ Ready ของ VC นี้กลับไปให้ผู้ส่ง
            assign s_ready[v] = ~fifo_full;

            // Instantiate Synchronous FIFO สำหรับเลนนี้
            sync_fifo #(
                .DATA_WIDTH(PACK_W),
                .DEPTH(DEPTH)
            ) vc_fifo_inst (
                .clk(clk),
                .rst_n(rst_n),
                .w_en(fifo_we && !fifo_full),
                .w_data(wdata),
                .r_en(m_ready[v] && !fifo_empty),
                .r_data(rdata),
                .full(fifo_full),
                .empty(fifo_empty)
            );

            // กระจายข้อมูลที่อ่านได้ออกจาก FIFO
            assign m_valid[v] = ~fifo_empty;
            assign m_tlast[v] = rdata[PACK_W-1];
            assign m_tdest[v] = rdata[DATA_W+3 : DATA_W];
            assign m_tdata[v] = rdata[DATA_W-1 : 0];

        end
    endgenerate

endmodule

