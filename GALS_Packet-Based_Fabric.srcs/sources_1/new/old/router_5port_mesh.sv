`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/30/2026 11:25:38 PM
// Design Name: 
// Module Name: router_5port_mesh
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


module router_5port_mesh #(
    parameter DATA_W = 8,
    // ระบบพิกัด (เช่น 2-bit X, 2-bit Y รองรับสูงสุด 4x4 = 16 Nodes)
    parameter CORD_W = 2, 
    parameter MY_X   = 2'd0, // พิกัด X ของ Router ตัวนี้ (เซ็ตตอน Instantiate)
    parameter MY_Y   = 2'd0  // พิกัด Y ของ Router ตัวนี้ (เซ็ตตอน Instantiate)
)(
    input logic clk,
    input logic rst_n,

    // ----------------------------------------------------
    // พอร์ตทั้ง 5 (0:Local, 1:North, 2:South, 3:East, 4:West)
    // ----------------------------------------------------
    input  logic [4:0]                  s_valid,
    input  logic [4:0]                  s_tlast,
    input  logic [4:0][(CORD_W*2)-1:0]  s_tdest, // {DEST_Y, DEST_X}
    input  logic [4:0][DATA_W-1:0]      s_tdata,
    output logic [4:0]                  s_ready,

    output logic [4:0]                  m_valid,
    output logic [4:0]                  m_tlast,
    output logic [4:0][(CORD_W*2)-1:0]  m_tdest,
    output logic [4:0][DATA_W-1:0]      m_tdata,
    input  logic [4:0]                  m_ready
);

    // นิยาม Index ของพอร์ตให้โค้ดอ่านง่าย
    localparam L = 0, N = 1, S = 2, E = 3, W = 4;

    // ==========================================
    // ด่านที่ 1: X-Y Routing Decoders (ขอทาง)
    // ==========================================
    logic [4:0] req_to [4:0]; // req_to[Output_Port][Input_Port]
    
    always_comb begin
        // รีเซ็ตคำขอทั้งหมดเป็น 0
        for (int out_p = 0; out_p < 5; out_p++) req_to[out_p] = 5'b0;

        // วนลูปตรวจสอบ Input ทีละพอร์ต (0 ถึง 4)
        for (int in_p = 0; in_p < 5; in_p++) begin
            if (s_valid[in_p]) begin
                automatic logic [CORD_W-1:0] dest_x = s_tdest[in_p][CORD_W-1:0];       // ครึ่งล่างคือ X
                automatic logic [CORD_W-1:0] dest_y = s_tdest[in_p][CORD_W*2-1:CORD_W]; // ครึ่งบนคือ Y

                // X-Y Routing Algorithm
                if      (dest_x > MY_X) req_to[E][in_p] = 1'b1; // ไปตะวันออก
                else if (dest_x < MY_X) req_to[W][in_p] = 1'b1; // ไปตะวันตก
                else if (dest_y > MY_Y) req_to[N][in_p] = 1'b1; // ไปทิศเหนือ
                else if (dest_y < MY_Y) req_to[S][in_p] = 1'b1; // ไปทิศใต้
                else                    req_to[L][in_p] = 1'b1; // ถึงบ้านแล้ว (Local)
            end
        end
    end

    // ==========================================
    // ด่านที่ 2: Packet Arbiters (5 ตัว ประจำ 5 ทางออก)
    // ==========================================
    logic [4:0] grant_out [4:0]; // grant_out[Output_Port]

    genvar i;
    generate
        for (i = 0; i < 5; i++) begin : gen_arbiters
            // ใช้ packet_arbiter ตัวเทพที่เรารองรับ TLAST-Locking
            packet_arbiter #(.PORTS(5)) arb (
                .clk(clk), 
                .rst_n(rst_n),
                .valid(req_to[i]),    // ใครขอมาพอร์ต Output 'i' บ้าง?
                .tlast(s_tlast),      // สัญญาณปลดล็อค
                .ready(m_ready[i]),   // ปลายทางพอร์ต 'i' ว่างไหม?
                .grant(grant_out[i])  // ให้สิทธิ์ Input ไหน?
            );
        end
    endgenerate

    // ==========================================
    // ด่านที่ 3: The Crossbar Multiplexers (5x5)
    // ==========================================
    generate
        for (i = 0; i < 5; i++) begin : gen_muxes
            assign m_valid[i] = |(grant_out[i] & req_to[i]);

            always_comb begin
                // Default fallback
                m_tdata[i] = '0; m_tlast[i] = 1'b0; m_tdest[i] = '0;
                
                // MUX: ตรวจสอบว่า Arbiter ให้สิทธิ์ Input ไหน 
                // แล้วเอา Data ของ Input นั้นส่งทะลุมายัง Output 'i'
                if      (grant_out[i][L]) begin m_tdata[i] = s_tdata[L]; m_tlast[i] = s_tlast[L]; m_tdest[i] = s_tdest[L]; end
                else if (grant_out[i][N]) begin m_tdata[i] = s_tdata[N]; m_tlast[i] = s_tlast[N]; m_tdest[i] = s_tdest[N]; end
                else if (grant_out[i][S]) begin m_tdata[i] = s_tdata[S]; m_tlast[i] = s_tlast[S]; m_tdest[i] = s_tdest[S]; end
                else if (grant_out[i][E]) begin m_tdata[i] = s_tdata[E]; m_tlast[i] = s_tlast[E]; m_tdest[i] = s_tdest[E]; end
                else if (grant_out[i][W]) begin m_tdata[i] = s_tdata[W]; m_tlast[i] = s_tlast[W]; m_tdest[i] = s_tdest[W]; end
            end
        end
    endgenerate

    // ==========================================
    // ด่านที่ 4: Ready Backpressure (สับสวิตช์ย้อนกลับ)
    // ==========================================
    generate
        for (i = 0; i < 5; i++) begin : gen_ready_back
            // Input 'i' จะได้ไฟเขียว (ready=1) ก็ต่อเมื่อ...
            // มันถูกเลือกโดย Output '0' และ Output '0' พร้อมรับ หรือ
            // มันถูกเลือกโดย Output '1' และ Output '1' พร้อมรับ ...ไปเรื่อยๆ
            assign s_ready[i] = (grant_out[L][i] & m_ready[L]) |
                                (grant_out[N][i] & m_ready[N]) |
                                (grant_out[S][i] & m_ready[S]) |
                                (grant_out[E][i] & m_ready[E]) |
                                (grant_out[W][i] & m_ready[W]);
        end
    endgenerate

endmodule

