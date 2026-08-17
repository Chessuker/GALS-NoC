`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/01/2026 03:20:45 PM
// Design Name: 
// Module Name: noc_mesh_2x2
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


module noc_mesh_2x2 #(
    parameter DATA_W = 8,
    parameter CORD_W = 2
)(
    input logic clk,
    input logic rst_n,

    // -----------------------------------------------------------------
    // พอร์ตเชื่อมต่อภายนอก (4 Local Ports สำหรับต่อ Compute/Memory Nodes)
    // -----------------------------------------------------------------
    // Node 00 @ พิกัด (0,0)
    input  logic                      s_node00_valid,
    input  logic                      s_node00_tlast,
    input  logic [(CORD_W*2)-1:0]     s_node00_tdest,
    input  logic [DATA_W-1:0]         s_node00_tdata,
    output logic                      s_node00_ready,
    output logic                      m_node00_valid,
    output logic                      m_node00_tlast,
    output logic [(CORD_W*2)-1:0]     m_node00_tdest,
    output logic [DATA_W-1:0]         m_node00_tdata,
    input  logic                      m_node00_ready,

    // Node 10 @ พิกัด (1,0)
    input  logic                      s_node10_valid,
    input  logic                      s_node10_tlast,
    input  logic [(CORD_W*2)-1:0]     s_node10_tdest,
    input  logic [DATA_W-1:0]         s_node10_tdata,
    output logic                      s_node10_ready,
    output logic                      m_node10_valid,
    output logic                      m_node10_tlast,
    output logic [(CORD_W*2)-1:0]     m_node10_tdest,
    output logic [DATA_W-1:0]         m_node10_tdata,
    input  logic                      m_node10_ready,

    // Node 01 @ พิกัด (0,1)
    input  logic                      s_node01_valid,
    input  logic                      s_node01_tlast,
    input  logic [(CORD_W*2)-1:0]     s_node01_tdest,
    input  logic [DATA_W-1:0]         s_node01_tdata,
    output logic                      s_node01_ready,
    output logic                      m_node01_valid,
    output logic                      m_node01_tlast,
    output logic [(CORD_W*2)-1:0]     m_node01_tdest,
    output logic [DATA_W-1:0]         m_node01_tdata,
    input  logic                      m_node01_ready,

    // Node 11 @ พิกัด (1,1)
    input  logic                      s_node11_valid,
    input  logic                      s_node11_tlast,
    input  logic [(CORD_W*2)-1:0]     s_node11_tdest,
    input  logic [DATA_W-1:0]         s_node11_tdata,
    output logic                      s_node11_ready,
    output logic                      m_node11_valid,
    output logic                      m_node11_tlast,
    output logic [(CORD_W*2)-1:0]     m_node11_tdest,
    output logic [DATA_W-1:0]         m_node11_tdata,
    input  logic                      m_node11_ready
);

    // นิยามพอร์ต: L=0, N=1, S=2, E=3, W=4
    localparam L = 0, N = 1, S = 2, E = 3, W = 4;

    // =================================================================
    // สายไฟภายในเชื่อมต่อระหว่างเราเตอร์ (Internal Channel Wires)
    // =================================================================
    // ทิศทางจาก (0,0) ไป (1,0) [Horizontal Low]
    logic v_00_to_10, l_00_to_10, r_00_to_10; logic [(CORD_W*2)-1:0] dest_00_to_10; logic [DATA_W-1:0] data_00_to_10;
    // ทิศทางจาก (1,0) ไป (0,0)
    logic v_10_to_00, l_10_to_00, r_10_to_00; logic [(CORD_W*2)-1:0] dest_10_to_00; logic [DATA_W-1:0] data_10_to_00;

    // ทิศทางจาก (0,1) ไป (1,1) [Horizontal High]
    logic v_01_to_11, l_01_to_11, r_01_to_11; logic [(CORD_W*2)-1:0] dest_01_to_11; logic [DATA_W-1:0] data_01_to_11;
    // ทิศทางจาก (1,1) ไป (0,1)
    logic v_11_to_01, l_11_to_01, r_11_to_01; logic [(CORD_W*2)-1:0] dest_11_to_01; logic [DATA_W-1:0] data_11_to_01;

    // ทิศทางจาก (0,0) ไป (0,1) [Vertical Left]
    logic v_00_to_01, l_00_to_01, r_00_to_01; logic [(CORD_W*2)-1:0] dest_00_to_01; logic [DATA_W-1:0] data_00_to_01;
    // ทิศทางจาก (0,1) ไป (0,0)
    logic v_01_to_00, l_01_to_00, r_01_to_00; logic [(CORD_W*2)-1:0] dest_01_to_00; logic [DATA_W-1:0] data_01_to_00;

    // ทิศทางจาก (1,0) ไป (1,1) [Vertical Right]
    logic v_10_to_11, l_10_to_11, r_10_to_11; logic [(CORD_W*2)-1:0] dest_10_to_11; logic [DATA_W-1:0] data_10_to_11;
    // ทิศทางจาก (1,1) ไป (1,0)
    logic v_11_to_10, l_11_to_10, r_11_to_10; logic [(CORD_W*2)-1:0] dest_11_to_10; logic [DATA_W-1:0] data_11_to_10;

    // =================================================================
    // 1. ROUTER NODE (0,0) - อยู่มุมซ้ายล่าง
    // =================================================================
    logic [4:0] s_val_00, s_lst_00, s_rdy_00, m_val_00, m_lst_00, m_rdy_00;
    logic [4:0][(CORD_W*2)-1:0] s_dst_00, m_dst_00;
    logic [4:0][DATA_W-1:0]     s_dta_00, m_dta_00;

    // ต่อพอร์ตภายนอกเข้า Local
    assign s_val_00[L] = s_node00_valid; assign s_lst_00[L] = s_node00_tlast; assign s_dst_00[L] = s_node00_tdest; assign s_dta_00[L] = s_node00_tdata; assign s_node00_ready = s_rdy_00[L];
    assign m_node00_valid = m_val_00[L]; assign m_node00_tlast = m_lst_00[L]; assign m_node00_tdest = m_dst_00[L]; assign m_node00_tdata = m_dta_00[L]; assign m_rdy_00[L] = m_node00_ready;
    // ต่อพอร์ตภายใน (เหนือ ต่อกับ 01, ออก ต่อกับ 10)
    assign s_val_00[N] = v_01_to_00; assign s_lst_00[N] = l_01_to_00; assign s_dst_00[N] = dest_01_to_00; assign s_dta_00[N] = data_01_to_00; assign r_01_to_00 = s_rdy_00[N];
    assign s_val_00[E] = v_10_to_00; assign s_lst_00[E] = l_10_to_00; assign s_dst_00[E] = dest_10_to_00; assign s_dta_00[E] = data_10_to_00; assign r_10_to_00 = s_rdy_00[E];
    assign v_00_to_01 = m_val_00[N]; assign l_00_to_01 = m_lst_00[N]; assign dest_00_to_01 = m_dst_00[N]; assign data_00_to_01 = m_dta_00[N]; assign m_rdy_00[N] = r_00_to_01;
    assign v_00_to_10 = m_val_00[E]; assign l_00_to_10 = m_lst_00[E]; assign dest_00_to_10 = m_dst_00[E]; assign data_00_to_10 = m_dta_00[E]; assign m_rdy_00[E] = r_00_to_10;
    // เคลียร์พอร์ตขอบสนาม (ใต้, ตก ไม่มีคนต่อด้วย)
    assign s_val_00[S] = 1'b0; assign s_lst_00[S] = 1'b0; assign s_dst_00[S] = '0; assign s_dta_00[S] = '0; assign m_rdy_00[S] = 1'b0;
    assign s_val_00[W] = 1'b0; assign s_lst_00[W] = 1'b0; assign s_dst_00[W] = '0; assign s_dta_00[W] = '0; assign m_rdy_00[W] = 1'b0;

    router_5port_mesh #(.DATA_W(DATA_W), .CORD_W(CORD_W), .MY_X(2'd0), .MY_Y(2'd0)) r_node_00 (
        .clk(clk), .rst_n(rst_n),
        .s_valid(s_val_00), .s_tlast(s_lst_00), .s_tdest(s_dst_00), .s_tdata(s_dta_00), .s_ready(s_rdy_00),
        .m_valid(m_val_00), .m_tlast(m_lst_00), .m_tdest(m_dst_00), .m_tdata(m_dta_00), .m_ready(m_rdy_00)
    );

    // =================================================================
    // 2. ROUTER NODE (1,0) - อยู่มุมขวาล่าง
    // =================================================================
    logic [4:0] s_val_10, s_lst_10, s_rdy_10, m_val_10, m_lst_10, m_rdy_10;
    logic [4:0][(CORD_W*2)-1:0] s_dst_10, m_dst_10;
    logic [4:0][DATA_W-1:0]     s_dta_10, m_dta_10;

    assign s_val_10[L] = s_node10_valid; assign s_lst_10[L] = s_node10_tlast; assign s_dst_10[L] = s_node10_tdest; assign s_dta_10[L] = s_node10_tdata; assign s_node10_ready = s_rdy_10[L];
    assign m_node10_valid = m_val_10[L]; assign m_node10_tlast = m_lst_10[L]; assign m_node10_tdest = m_dst_10[L]; assign m_node10_tdata = m_dta_10[L]; assign m_rdy_10[L] = m_node10_ready;
    // พอร์ตภายใน (เหนือ ต่อกับ 11, ตก ต่อกับ 00)
    assign s_val_10[N] = v_11_to_10; assign s_lst_10[N] = l_11_to_10; assign s_dst_10[N] = dest_11_to_10; assign s_dta_10[N] = data_11_to_10; assign r_11_to_10 = s_rdy_10[N];
    assign s_val_10[W] = v_00_to_10; assign s_lst_10[W] = l_00_to_10; assign s_dst_10[W] = dest_00_to_10; assign s_dta_10[W] = data_00_to_10; assign r_00_to_10 = s_rdy_10[W];
    assign v_10_to_11 = m_val_10[N]; assign l_10_to_11 = m_lst_10[N]; assign dest_10_to_11 = m_dst_10[N]; assign data_10_to_11 = m_dta_10[N]; assign m_rdy_10[N] = r_10_to_11;
    assign v_10_to_00 = m_val_10[W]; assign l_10_to_00 = m_lst_10[W]; assign dest_10_to_00 = m_dst_10[W]; assign data_10_to_00 = m_dta_10[W]; assign m_rdy_10[W] = r_10_to_00;
    // พอร์ตขอบสนาม (ใต้, ออก ไม่มีคนต่อด้วย)
    assign s_val_10[S] = 1'b0; assign s_lst_10[S] = 1'b0; assign s_dst_10[S] = '0; assign s_dta_10[S] = '0; assign m_rdy_10[S] = 1'b0;
    assign s_val_10[E] = 1'b0; assign s_lst_10[E] = 1'b0; assign s_dst_10[E] = '0; assign s_dta_10[E] = '0; assign m_rdy_10[E] = 1'b0;

    router_5port_mesh #(.DATA_W(DATA_W), .CORD_W(CORD_W), .MY_X(2'd1), .MY_Y(2'd0)) r_node_10 (
        .clk(clk), .rst_n(rst_n),
        .s_valid(s_val_10), .s_tlast(s_lst_10), .s_tdest(s_dst_10), .s_tdata(s_dta_10), .s_ready(s_rdy_10),
        .m_valid(m_val_10), .m_tlast(m_lst_10), .m_tdest(m_dst_10), .m_tdata(m_dta_10), .m_ready(m_rdy_10)
    );

    // =================================================================
    // 3. ROUTER NODE (0,1) - อยู่มุมซ้ายบน
    // =================================================================
    logic [4:0] s_val_01, s_lst_01, s_rdy_01, m_val_01, m_lst_01, m_rdy_01;
    logic [4:0][(CORD_W*2)-1:0] s_dst_01, m_dst_01;
    logic [4:0][DATA_W-1:0]     s_dta_01, m_dta_01;

    assign s_val_01[L] = s_node01_valid; assign s_lst_01[L] = s_node01_tlast; assign s_dst_01[L] = s_node01_tdest; assign s_dta_01[L] = s_node01_tdata; assign s_node01_ready = s_rdy_01[L];
    assign m_node01_valid = m_val_01[L]; assign m_node01_tlast = m_lst_01[L]; assign m_node01_tdest = m_dst_01[L]; assign m_node01_tdata = m_dta_01[L]; assign m_rdy_01[L] = m_node01_ready;
    // พอร์ตภายใน (ใต้ ต่อกับ 00, ออก ต่อกับ 11)
    assign s_val_01[S] = v_00_to_01; assign s_lst_01[S] = l_00_to_01; assign s_dst_01[S] = dest_00_to_01; assign s_dta_01[S] = data_00_to_01; assign r_00_to_01 = s_rdy_01[S];
    assign s_val_01[E] = v_11_to_01; assign s_lst_01[E] = l_11_to_01; assign s_dst_01[E] = dest_11_to_01; assign s_dta_01[E] = data_11_to_01; assign r_11_to_01 = s_rdy_01[E];
    assign v_01_to_00 = m_val_01[S]; assign l_01_to_00 = m_lst_01[S]; assign dest_01_to_00 = m_dst_01[S]; assign data_01_to_00 = m_dta_01[S]; assign m_rdy_01[S] = r_01_to_00;
    assign v_01_to_11 = m_val_01[E]; assign l_01_to_11 = m_lst_01[E]; assign dest_01_to_11 = m_dst_01[E]; assign data_01_to_11 = m_dta_01[E]; assign m_rdy_01[E] = r_01_to_11;
    // พอร์ตขอบสนาม (เหนือ, ตก ไม่มีคนต่อด้วย)
    assign s_val_01[N] = 1'b0; assign s_lst_01[N] = 1'b0; assign s_dst_01[N] = '0; assign s_dta_01[N] = '0; assign m_rdy_01[N] = 1'b0;
    assign s_val_01[W] = 1'b0; assign s_lst_01[W] = 1'b0; assign s_dst_01[W] = '0; assign s_dta_01[W] = '0; assign m_rdy_01[W] = 1'b0;

    router_5port_mesh #(.DATA_W(DATA_W), .CORD_W(CORD_W), .MY_X(2'd0), .MY_Y(2'd1)) r_node_01 (
        .clk(clk), .rst_n(rst_n),
        .s_valid(s_val_01), .s_tlast(s_lst_01), .s_tdest(s_dst_01), .s_tdata(s_dta_01), .s_ready(s_rdy_01),
        .m_valid(m_val_01), .m_tlast(m_lst_01), .m_tdest(m_dst_01), .m_tdata(m_dta_01), .m_ready(m_rdy_01)
    );

    // =================================================================
    // 4. ROUTER NODE (1,1) - อยู่มุมขวาบน
    // =================================================================
    logic [4:0] s_val_11, s_lst_11, s_rdy_11, m_val_11, m_lst_11, m_rdy_11;
    logic [4:0][(CORD_W*2)-1:0] s_dst_11, m_dst_11;
    logic [4:0][DATA_W-1:0]     s_dta_11, m_dta_11;

    assign s_val_11[L] = s_node11_valid; assign s_lst_11[L] = s_node11_tlast; assign s_dst_11[L] = s_node11_tdest; assign s_dta_11[L] = s_node11_tdata; assign s_node11_ready = s_rdy_11[L];
    assign m_node11_valid = m_val_11[L]; assign m_node11_tlast = m_lst_11[L]; assign m_node11_tdest = m_dst_11[L]; assign m_node11_tdata = m_dta_11[L]; assign m_rdy_11[L] = m_node11_ready;
    // พอร์ตภายใน (ใต้ ต่อกับ 10, ตก ต่อกับ 01)
    assign s_val_11[S] = v_10_to_11; assign s_lst_11[S] = l_10_to_11; assign s_dst_11[S] = dest_10_to_11; assign s_dta_11[S] = data_10_to_11; assign r_10_to_11 = s_rdy_11[S];
    assign s_val_11[W] = v_01_to_11; assign s_lst_11[W] = l_01_to_11; assign s_dst_11[W] = dest_01_to_11; assign s_dta_11[W] = data_01_to_11; assign r_01_to_11 = s_rdy_11[W];
    assign v_11_to_10 = m_val_11[S]; assign l_11_to_10 = m_lst_11[S]; assign dest_11_to_10 = m_dst_11[S]; assign data_11_to_10 = m_dta_11[S]; assign m_rdy_11[S] = r_11_to_10;
    assign v_11_to_01 = m_val_11[W]; assign l_11_to_01 = m_lst_11[W]; assign dest_11_to_01 = m_dst_11[W]; assign data_11_to_01 = m_dta_11[W]; assign m_rdy_11[W] = r_11_to_01;
    // พอร์ตขอบสนาม (เหนือ, ออก ไม่มีคนต่อด้วย)
    assign s_val_11[N] = 1'b0; assign s_lst_11[N] = 1'b0; assign s_dst_11[N] = '0; assign s_dta_11[N] = '0; assign m_rdy_11[N] = 1'b0;
    assign s_val_11[E] = 1'b0; assign s_lst_11[E] = 1'b0; assign s_dst_11[E] = '0; assign s_dta_11[E] = '0; assign m_rdy_11[E] = 1'b0;

    router_5port_mesh #(.DATA_W(DATA_W), .CORD_W(CORD_W), .MY_X(2'd1), .MY_Y(2'd1)) r_node_11 (
        .clk(clk), .rst_n(rst_n),
        .s_valid(s_val_11), .s_tlast(s_lst_11), .s_tdest(s_dst_11), .s_tdata(s_dta_11), .s_ready(s_rdy_11),
        .m_valid(m_val_11), .m_tlast(m_lst_11), .m_tdest(m_dst_11), .m_tdata(m_dta_11), .m_ready(m_rdy_11)
    );

endmodule