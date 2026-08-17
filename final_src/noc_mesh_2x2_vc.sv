`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/03/2026 10:43:24 PM
// Design Name: 
// Module Name: noc_mesh_2x2_vc
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


module noc_mesh_2x2_vc #(
    parameter DATA_W = 8,
    parameter CORD_W = 2,
    parameter NUM_VCS = 2,
    parameter DEPTH = 16
)(
    input  logic clk,
    input  logic rst_n,

    // 4 Nodes Interface (0: x0y0, 1: x1y0, 2: x0y1, 3: x1y1)
    input  logic [3:0]              s_valid,
    input  logic [3:0]              s_tlast,
    input  logic [3:0][3:0]         s_tdest,
    input  logic [3:0][DATA_W-1:0]  s_tdata,
    input  logic [3:0][NUM_VCS-1:0] s_tid,
    output logic [3:0][NUM_VCS-1:0] s_ready,

    output logic [3:0]              m_valid,
    output logic [3:0]              m_tlast,
    output logic [3:0][3:0]         m_tdest,
    output logic [3:0][DATA_W-1:0]  m_tdata,
    output logic [3:0][NUM_VCS-1:0] m_tid,
    input  logic [3:0][NUM_VCS-1:0] m_ready
);

    localparam LOCAL = 0, NORTH = 1, SOUTH = 2, EAST = 3, WEST = 4;

    // =================================================================
    // สายไฟภายใน (Internal Wires) สำหรับเชื่อมระหว่างพอร์ต
    // [Router_Index][Port_Index]
    // =================================================================
    logic [4:0]              r_valid [4];
    logic [4:0]              r_last  [4];
    logic [4:0][3:0]         r_dst   [4];
    logic [4:0][DATA_W-1:0]  r_dat   [4];
    logic [4:0][NUM_VCS-1:0] r_tid   [4];
    logic [4:0][NUM_VCS-1:0] r_rdy   [4];

    logic [4:0]              m_valid_wire [4];
    logic [4:0]              m_last_wire  [4];
    logic [4:0][3:0]         m_dst_wire   [4];
    logic [4:0][DATA_W-1:0]  m_dat_wire   [4];
    logic [4:0][NUM_VCS-1:0] m_tid_wire   [4];
    logic [4:0][NUM_VCS-1:0] m_rdy_wire   [4];

    // =================================================================
    // 1. วาง Router 4 ตัว ลงบนกระดาน (Instantiation)
    // =================================================================
    genvar x, y;
    generate
        for (y = 0; y < 2; y++) begin : ROW
            for (x = 0; x < 2; x++) begin : COL
                localparam int idx = y * 2 + x;
                
                router_5port_mesh_vc #(
                    .MY_X(x[1:0]), .MY_Y(y[1:0]), .DATA_W(DATA_W), .CORD_W(CORD_W), .NUM_VCS(NUM_VCS), .DEPTH(DEPTH)
                ) router (
                    .clk(clk), .rst_n(rst_n),
                    .s_valid(r_valid[idx]), .s_tlast(r_last[idx]), .s_tdest(r_dst[idx]), .s_tdata(r_dat[idx]), .s_tid(r_tid[idx]), .s_ready(r_rdy[idx]),
                    .m_valid(m_valid_wire[idx]), .m_tlast(m_last_wire[idx]), .m_tdest(m_dst_wire[idx]), .m_tdata(m_dat_wire[idx]), .m_tid(m_tid_wire[idx]), .m_ready(m_rdy_wire[idx])
                );
            end
        end
    endgenerate

    // =================================================================
    // 2. เดินสายไฟ (WIRING LOGIC) ⚡
    // =================================================================
    generate
        for (genvar i = 0; i < 4; i++) begin : LOCAL_PORTS
            // 2.1 เชื่อมพอร์ต LOCAL (0) ลงไปหา Host (ผ่าน Wrapper)
            assign r_valid[i][LOCAL] = s_valid[i];
            assign r_last[i][LOCAL]  = s_tlast[i];
            assign r_dst[i][LOCAL]   = s_tdest[i];
            assign r_dat[i][LOCAL]   = s_tdata[i];
            assign r_tid[i][LOCAL]   = s_tid[i];
            assign s_ready[i]        = r_rdy[i][LOCAL];

            assign m_valid[i] = m_valid_wire[i][LOCAL];
            assign m_tlast[i] = m_last_wire[i][LOCAL];
            assign m_tdest[i] = m_dst_wire[i][LOCAL];
            assign m_tdata[i] = m_dat_wire[i][LOCAL];
            assign m_tid[i]   = m_tid_wire[i][LOCAL];
            assign m_rdy_wire[i][LOCAL] = m_ready[i];
        end
    endgenerate

    // 2.2 เชื่อมแกนนอน (X-Axis: EAST <-> WEST)
    // Node 00 (idx 0) <-----> Node 10 (idx 1)
    assign r_valid[1][WEST] = m_valid_wire[0][EAST];
    assign r_last[1][WEST]  = m_last_wire[0][EAST];
    assign r_dst[1][WEST]   = m_dst_wire[0][EAST];
    assign r_dat[1][WEST]   = m_dat_wire[0][EAST];
    assign r_tid[1][WEST]   = m_tid_wire[0][EAST];
    assign m_rdy_wire[0][EAST] = r_rdy[1][WEST];

    assign r_valid[0][EAST] = m_valid_wire[1][WEST];
    assign r_last[0][EAST]  = m_last_wire[1][WEST];
    assign r_dst[0][EAST]   = m_dst_wire[1][WEST];
    assign r_dat[0][EAST]   = m_dat_wire[1][WEST];
    assign r_tid[0][EAST]   = m_tid_wire[1][WEST];
    assign m_rdy_wire[1][WEST] = r_rdy[0][EAST];

    // Node 01 (idx 2) <-----> Node 11 (idx 3)
    assign r_valid[3][WEST] = m_valid_wire[2][EAST];
    assign r_last[3][WEST]  = m_last_wire[2][EAST];
    assign r_dst[3][WEST]   = m_dst_wire[2][EAST];
    assign r_dat[3][WEST]   = m_dat_wire[2][EAST];
    assign r_tid[3][WEST]   = m_tid_wire[2][EAST];
    assign m_rdy_wire[2][EAST] = r_rdy[3][WEST];

    assign r_valid[2][EAST] = m_valid_wire[3][WEST];
    assign r_last[2][EAST]  = m_last_wire[3][WEST];
    assign r_dst[2][EAST]   = m_dst_wire[3][WEST];
    assign r_dat[2][EAST]   = m_dat_wire[3][WEST];
    assign r_tid[2][EAST]   = m_tid_wire[3][WEST];
    assign m_rdy_wire[3][WEST] = r_rdy[2][EAST];

    // 2.3 เชื่อมแกนตั้ง (Y-Axis: NORTH <-> SOUTH)
    // Node 00 (idx 0) <-----> Node 01 (idx 2)
    assign r_valid[2][SOUTH] = m_valid_wire[0][NORTH];
    assign r_last[2][SOUTH]  = m_last_wire[0][NORTH];
    assign r_dst[2][SOUTH]   = m_dst_wire[0][NORTH];
    assign r_dat[2][SOUTH]   = m_dat_wire[0][NORTH];
    assign r_tid[2][SOUTH]   = m_tid_wire[0][NORTH];
    assign m_rdy_wire[0][NORTH] = r_rdy[2][SOUTH];

    assign r_valid[0][NORTH] = m_valid_wire[2][SOUTH];
    assign r_last[0][NORTH]  = m_last_wire[2][SOUTH];
    assign r_dst[0][NORTH]   = m_dst_wire[2][SOUTH];
    assign r_dat[0][NORTH]   = m_dat_wire[2][SOUTH];
    assign r_tid[0][NORTH]   = m_tid_wire[2][SOUTH];
    assign m_rdy_wire[2][SOUTH] = r_rdy[0][NORTH];

    // Node 10 (idx 1) <-----> Node 11 (idx 3)
    assign r_valid[3][SOUTH] = m_valid_wire[1][NORTH];
    assign r_last[3][SOUTH]  = m_last_wire[1][NORTH];
    assign r_dst[3][SOUTH]   = m_dst_wire[1][NORTH];
    assign r_dat[3][SOUTH]   = m_dat_wire[1][NORTH];
    assign r_tid[3][SOUTH]   = m_tid_wire[1][NORTH];
    assign m_rdy_wire[1][NORTH] = r_rdy[3][SOUTH];

    assign r_valid[1][NORTH] = m_valid_wire[3][SOUTH];
    assign r_last[1][NORTH]  = m_last_wire[3][SOUTH];
    assign r_dst[1][NORTH]   = m_dst_wire[3][SOUTH];
    assign r_dat[1][NORTH]   = m_dat_wire[3][SOUTH];
    assign r_tid[1][NORTH]   = m_tid_wire[3][SOUTH];
    assign m_rdy_wire[3][SOUTH] = r_rdy[1][NORTH];

    // =================================================================
    // 3. ปิดขอบกระดาน (Tie-off) ป้องกัน Undefined State
    // =================================================================
    // Node 00 (X=0, Y=0): ทิศ SOUTH, WEST ติดขอบ
    assign r_valid[0][SOUTH] = 1'b0; assign m_rdy_wire[0][SOUTH] = '0;
    assign r_valid[0][WEST]  = 1'b0; assign m_rdy_wire[0][WEST]  = '0;
    
    // Node 10 (X=1, Y=0): ทิศ SOUTH, EAST ติดขอบ
    assign r_valid[1][SOUTH] = 1'b0; assign m_rdy_wire[1][SOUTH] = '0;
    assign r_valid[1][EAST]  = 1'b0; assign m_rdy_wire[1][EAST]  = '0;
    
    // Node 01 (X=0, Y=1): ทิศ NORTH, WEST ติดขอบ
    assign r_valid[2][NORTH] = 1'b0; assign m_rdy_wire[2][NORTH] = '0;
    assign r_valid[2][WEST]  = 1'b0; assign m_rdy_wire[2][WEST]  = '0;
    
    // Node 11 (X=1, Y=1): ทิศ NORTH, EAST ติดขอบ
    assign r_valid[3][NORTH] = 1'b0; assign m_rdy_wire[3][NORTH] = '0;
    assign r_valid[3][EAST]  = 1'b0; assign m_rdy_wire[3][EAST]  = '0;

endmodule