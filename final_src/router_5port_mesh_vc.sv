`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/03/2026 10:40:32 PM
// Design Name: 
// Module Name: router_5port_mesh_vc
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


module router_5port_mesh_vc #(
    parameter [1:0] MY_X = 2'd0,
    parameter [1:0] MY_Y = 2'd0,
    parameter DATA_W = 8,
    parameter CORD_W = 2,
    parameter NUM_VCS = 2,
    parameter DEPTH = 16
)(
    input  logic clk,
    input  logic rst_n,

    // 5 Input Ports (0:Local, 1:North, 2:South, 3:East, 4:West)
    input  logic [4:0]              s_valid,
    input  logic [4:0]              s_tlast,
    input  logic [4:0][3:0]         s_tdest,
    input  logic [4:0][DATA_W-1:0]  s_tdata,
    input  logic [4:0][NUM_VCS-1:0] s_tid,
    output logic [4:0][NUM_VCS-1:0] s_ready,

    // 5 Output Ports
    output logic [4:0]              m_valid,
    output logic [4:0]              m_tlast,
    output logic [4:0][3:0]         m_tdest,
    output logic [4:0][DATA_W-1:0]  m_tdata,
    output logic [4:0][NUM_VCS-1:0] m_tid,
    input  logic [4:0][NUM_VCS-1:0] m_ready
);

    localparam LOCAL = 0, NORTH = 1, SOUTH = 2, EAST = 3, WEST = 4;

    // =========================================================
    // 1. VC Input Buffers (กล่องคัดแยกจดหมาย 5 ทิศทาง)
    // =========================================================
    logic              buf_valid [5][NUM_VCS];
    logic              buf_tlast [5][NUM_VCS];
    logic [3:0]        buf_tdest [5][NUM_VCS];
    logic [DATA_W-1:0] buf_tdata [5][NUM_VCS];
    logic              buf_ready [5][NUM_VCS];

    generate
        for (genvar p = 0; p < 5; p++) begin : GEN_IN_BUF
            vc_input_buffer #(
                .DATA_W(DATA_W), .CORD_W(CORD_W), .NUM_VCS(NUM_VCS), .DEPTH(DEPTH)
            ) in_buf (
                .clk(clk), .rst_n(rst_n),
                .s_valid(s_valid[p]), .s_tlast(s_tlast[p]), .s_tdest(s_tdest[p]), .s_tdata(s_tdata[p]), .s_tid(s_tid[p]), .s_ready(s_ready[p]),
                .m_valid(buf_valid[p]), .m_tlast(buf_tlast[p]), .m_tdest(buf_tdest[p]), .m_tdata(buf_tdata[p]), .m_ready(buf_ready[p])
            );
        end
    endgenerate

    // =========================================================
    // 2. X-Y Routing Decoder (ดูจ่าหน้าซอง ว่าจะส่งออกพอร์ตไหน)
    // =========================================================
    logic [4:0] route_req [5][NUM_VCS]; // [in_port][vc][out_port]

    always_comb begin
        for (int in_p = 0; in_p < 5; in_p++) begin
            for (int vc = 0; vc < NUM_VCS; vc++) begin
                route_req[in_p][vc] = '0;
                if (buf_valid[in_p][vc]) begin
                    automatic logic [1:0] dx = buf_tdest[in_p][vc][3:2];
                    automatic logic [1:0] dy = buf_tdest[in_p][vc][1:0];

                    if      (dx > MY_X) route_req[in_p][vc][EAST]  = 1'b1;
                    else if (dx < MY_X) route_req[in_p][vc][WEST]  = 1'b1;
                    else if (dy > MY_Y) route_req[in_p][vc][NORTH] = 1'b1;
                    else if (dy < MY_Y) route_req[in_p][vc][SOUTH] = 1'b1;
                    else                route_req[in_p][vc][LOCAL] = 1'b1;
                end
            end
        end
    end

    // =========================================================
    // 3. Port Arbiters & Crossbar (สมองกลสับรางและทางแยก)
    // =========================================================
    logic [4:0] grant_vc0 [5]; // [out_port][in_port]
    logic [4:0] grant_vc1 [5];
    
    logic [4:0] req_out_vc0 [5]; // [out_port][in_port]
    logic [4:0] req_out_vc1 [5];
    logic [4:0] last_out_vc0 [5];
    logic [4:0] last_out_vc1 [5];

    logic ready_from_arb_vc0 [5];
    logic ready_from_arb_vc1 [5];

    // กระจาย Request เข้า Arbiter ประจำ Output Port
    always_comb begin
        for (int out_p = 0; out_p < 5; out_p++) begin
            for (int in_p = 0; in_p < 5; in_p++) begin
                req_out_vc0[out_p][in_p] = route_req[in_p][0][out_p];
                req_out_vc1[out_p][in_p] = route_req[in_p][1][out_p];
                last_out_vc0[out_p][in_p] = buf_tlast[in_p][0];
                last_out_vc1[out_p][in_p] = buf_tlast[in_p][1];
            end
        end
    end

    generate
        for (genvar out_p = 0; out_p < 5; out_p++) begin : GEN_OUT_PORT
            // สับราง 2 ชั้น (QoS -> Round Robin)
            vc_port_arbiter #(.PORTS(5)) port_arb (
                .clk(clk), .rst_n(rst_n),
                .valid_vc1(req_out_vc1[out_p]), .tlast_vc1(last_out_vc1[out_p]), .grant_vc1(grant_vc1[out_p]),
                .valid_vc0(req_out_vc0[out_p]), .tlast_vc0(last_out_vc0[out_p]), .grant_vc0(grant_vc0[out_p]),
                .ready_out_vc1(m_ready[out_p][1]), 
                .ready_out_vc0(m_ready[out_p][0]),
                .ready_vc1(ready_from_arb_vc1[out_p]),
                .ready_vc0(ready_from_arb_vc0[out_p])
            );

            // Crossbar MUX (ดึงข้อมูลผู้ชนะส่งออกไปที่สายไฟ)
            always_comb begin
                m_valid[out_p] = 1'b0;
                m_tlast[out_p] = 1'b0;
                m_tdest[out_p] = '0;
                m_tdata[out_p] = '0;
                m_tid[out_p]   = '0;

                // Priority MUX (VC1 ชนะเสมอถ้ามีรถพยาบาลวิ่งมา)
                if (|grant_vc1[out_p]) begin
                    for (int in_p = 0; in_p < 5; in_p++) begin
                        if (grant_vc1[out_p][in_p]) begin
                            m_valid[out_p] = buf_valid[in_p][1];
                            m_tlast[out_p] = buf_tlast[in_p][1];
                            m_tdest[out_p] = buf_tdest[in_p][1];
                            m_tdata[out_p] = buf_tdata[in_p][1];
                            m_tid[out_p]   = 2'b10; // แปะป้ายบอกว่าเป็นรถเลน VC1
                        end
                    end
                end else if (|grant_vc0[out_p]) begin
                    for (int in_p = 0; in_p < 5; in_p++) begin
                        if (grant_vc0[out_p][in_p]) begin
                            m_valid[out_p] = buf_valid[in_p][0];
                            m_tlast[out_p] = buf_tlast[in_p][0];
                            m_tdest[out_p] = buf_tdest[in_p][0];
                            m_tdata[out_p] = buf_tdata[in_p][0];
                            m_tid[out_p]   = 2'b01; // แปะป้ายบอกว่าเป็นรถเลน VC0
                        end
                    end
                end
            end
        end
    endgenerate

    // ดึงสัญญาณ Ready คืนกลับไปบอก Input Buffers (OR logic)
    always_comb begin
        for (int in_p = 0; in_p < 5; in_p++) begin
            buf_ready[in_p][0] = 1'b0;
            buf_ready[in_p][1] = 1'b0;
            for (int out_p = 0; out_p < 5; out_p++) begin
                if (grant_vc0[out_p][in_p]) buf_ready[in_p][0] |= ready_from_arb_vc0[out_p];
                if (grant_vc1[out_p][in_p]) buf_ready[in_p][1] |= ready_from_arb_vc1[out_p];
            end
        end
    end

endmodule
