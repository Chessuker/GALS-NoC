`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/14/2026 04:59:12 PM
// Design Name: 
// Module Name: gals_noc_top
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


module gals_noc_top (
    // --------------------------------------------------------
    // 🕒 Clock & Reset Pins
    // --------------------------------------------------------
    input  logic clk_noc,  // NoC Backbone Clock (e.g., 250MHz)
    input  logic rst_n,    // Global Active-Low Reset

    input  logic clk_h00,  // Host 00 Clock
    input  logic clk_h01,  // Host 01 Clock
    input  logic clk_h10,  // Host 10 Clock
    input  logic clk_h11,  // Host 11 Clock

    // --------------------------------------------------------
    // 🔌 Node 00 (x=0, y=0) Interface
    // --------------------------------------------------------
    input  logic [7:0] h00_tx_tdata,
    input  logic [3:0] h00_tx_tdest,
    input  logic [1:0] h00_tx_tid,
    input  logic       h00_tx_tlast,
    input  logic       h00_tx_tvalid,
    output logic [1:0] h00_tx_tready, // 🟢 อัปเกรดเป็น 2 บิต (VC0, VC1)

    output logic [7:0] h00_rx_tdata,
    output logic [3:0] h00_rx_tdest,
    output logic [1:0] h00_rx_tid,
    output logic       h00_rx_tlast,
    output logic       h00_rx_tvalid,
    input  logic [1:0] h00_rx_tready, // 🟢 อัปเกรดเป็น 2 บิต (VC0, VC1)

    // --------------------------------------------------------
    // 🔌 Node 01 (x=0, y=1) Interface
    // --------------------------------------------------------
    input  logic [7:0] h01_tx_tdata,
    input  logic [3:0] h01_tx_tdest,
    input  logic [1:0] h01_tx_tid,
    input  logic       h01_tx_tlast,
    input  logic       h01_tx_tvalid,
    output logic [1:0] h01_tx_tready, // 🟢 อัปเกรดเป็น 2 บิต

    output logic [7:0] h01_rx_tdata,
    output logic [3:0] h01_rx_tdest,
    output logic [1:0] h01_rx_tid,
    output logic       h01_rx_tlast,
    output logic       h01_rx_tvalid,
    input  logic [1:0] h01_rx_tready, // 🟢 อัปเกรดเป็น 2 บิต

    // --------------------------------------------------------
    // 🔌 Node 10 (x=1, y=0) Interface
    // --------------------------------------------------------
    input  logic [7:0] h10_tx_tdata,
    input  logic [3:0] h10_tx_tdest,
    input  logic [1:0] h10_tx_tid,
    input  logic       h10_tx_tlast,
    input  logic       h10_tx_tvalid,
    output logic [1:0] h10_tx_tready, // 🟢 อัปเกรดเป็น 2 บิต

    output logic [7:0] h10_rx_tdata,
    output logic [3:0] h10_rx_tdest,
    output logic [1:0] h10_rx_tid,
    output logic       h10_rx_tlast,
    output logic       h10_rx_tvalid,
    input  logic [1:0] h10_rx_tready, // 🟢 อัปเกรดเป็น 2 บิต

    // --------------------------------------------------------
    // 🔌 Node 11 (x=1, y=1) Interface
    // --------------------------------------------------------
    input  logic [7:0] h11_tx_tdata,
    input  logic [3:0] h11_tx_tdest,
    input  logic [1:0] h11_tx_tid,
    input  logic       h11_tx_tlast,
    input  logic       h11_tx_tvalid,
    output logic [1:0] h11_tx_tready, // 🟢 อัปเกรดเป็น 2 บิต

    output logic [7:0] h11_rx_tdata,
    output logic [3:0] h11_rx_tdest,
    output logic [1:0] h11_rx_tid,
    output logic       h11_rx_tlast,
    output logic       h11_rx_tvalid,
    input  logic [1:0] h11_rx_tready  // 🟢 อัปเกรดเป็น 2 บิต
);

    // ========================================================
    // 🧶 Internal Wires (สายไฟเชื่อม Wrapper <-> NoC Router)
    // ========================================================
    logic [3:0][7:0] noc_tx_tdata;
    logic [3:0][3:0] noc_tx_tdest;
    logic [3:0][1:0] noc_tx_tid;
    logic [3:0]      noc_tx_tlast;
    logic [3:0]      noc_tx_tvalid;
    logic [3:0][1:0] noc_tx_tready; 

    logic [3:0][7:0] noc_rx_tdata;
    logic [3:0][3:0] noc_rx_tdest;
    logic [3:0][1:0] noc_rx_tid;
    logic [3:0]      noc_rx_tlast;
    logic [3:0]      noc_rx_tvalid;
    logic [3:0][1:0] noc_rx_tready;

    // ========================================================
    // 🏢 Instantiations
    // ========================================================

    // --- 1. NoC Mesh 2x2 (แกนกลางเครือข่าย) ---
    noc_mesh_2x2_vc uut_noc (
        .clk        (clk_noc),
        .rst_n      (rst_n),
        .s_tdata    (noc_tx_tdata),
        .s_tdest    (noc_tx_tdest),
        .s_tid      (noc_tx_tid),
        .s_tlast    (noc_tx_tlast),
        .s_valid    (noc_tx_tvalid),
        .s_ready    (noc_tx_tready),
        .m_tdata    (noc_rx_tdata),
        .m_tdest    (noc_rx_tdest),
        .m_tid      (noc_rx_tid),
        .m_tlast    (noc_rx_tlast),
        .m_valid    (noc_rx_tvalid),
        .m_ready    (noc_rx_tready)
    );

    // --- 2. GALS Wrappers (สะพานเชื่อมโดเมนนาฬิกา) ---

    // [Index 0] Node 00
    gals_node_wrapper wrap_00 (
        .clk_noc(clk_noc), .clk_host(clk_h00), .rst_n(rst_n),
        .s_host_tdata(h00_tx_tdata), .s_host_tdest(h00_tx_tdest), .s_host_tid(h00_tx_tid), 
        .s_host_tlast(h00_tx_tlast), .s_host_valid(h00_tx_tvalid), .s_host_ready(h00_tx_tready),
        .m_host_tdata(h00_rx_tdata), .m_host_tdest(h00_rx_tdest), .m_host_tid(h00_rx_tid), 
        .m_host_tlast(h00_rx_tlast), .m_host_valid(h00_rx_tvalid), .m_host_ready(h00_rx_tready),
        .m_noc_tdata(noc_tx_tdata[0]), .m_noc_tdest(noc_tx_tdest[0]), .m_noc_tid(noc_tx_tid[0]), 
        .m_noc_tlast(noc_tx_tlast[0]), .m_noc_valid(noc_tx_tvalid[0]), .m_noc_ready(noc_tx_tready[0]),
        .s_noc_tdata(noc_rx_tdata[0]), .s_noc_tdest(noc_rx_tdest[0]), .s_noc_tid(noc_rx_tid[0]), 
        .s_noc_tlast(noc_rx_tlast[0]), .s_noc_valid(noc_rx_tvalid[0]), .s_noc_ready(noc_rx_tready[0])
    );

    // [Index 1] Node 01
    gals_node_wrapper wrap_01 (
        .clk_noc(clk_noc), .clk_host(clk_h01), .rst_n(rst_n),
        .s_host_tdata(h01_tx_tdata), .s_host_tdest(h01_tx_tdest), .s_host_tid(h01_tx_tid), 
        .s_host_tlast(h01_tx_tlast), .s_host_valid(h01_tx_tvalid), .s_host_ready(h01_tx_tready),
        .m_host_tdata(h01_rx_tdata), .m_host_tdest(h01_rx_tdest), .m_host_tid(h01_rx_tid), 
        .m_host_tlast(h01_rx_tlast), .m_host_valid(h01_rx_tvalid), .m_host_ready(h01_rx_tready),
        .m_noc_tdata(noc_tx_tdata[1]), .m_noc_tdest(noc_tx_tdest[1]), .m_noc_tid(noc_tx_tid[1]), 
        .m_noc_tlast(noc_tx_tlast[1]), .m_noc_valid(noc_tx_tvalid[1]), .m_noc_ready(noc_tx_tready[1]),
        .s_noc_tdata(noc_rx_tdata[1]), .s_noc_tdest(noc_rx_tdest[1]), .s_noc_tid(noc_rx_tid[1]), 
        .s_noc_tlast(noc_rx_tlast[1]), .s_noc_valid(noc_rx_tvalid[1]), .s_noc_ready(noc_rx_tready[1])
    );

    // [Index 2] Node 10
    gals_node_wrapper wrap_10 (
        .clk_noc(clk_noc), .clk_host(clk_h10), .rst_n(rst_n),
        .s_host_tdata(h10_tx_tdata), .s_host_tdest(h10_tx_tdest), .s_host_tid(h10_tx_tid), 
        .s_host_tlast(h10_tx_tlast), .s_host_valid(h10_tx_tvalid), .s_host_ready(h10_tx_tready),
        .m_host_tdata(h10_rx_tdata), .m_host_tdest(h10_rx_tdest), .m_host_tid(h10_rx_tid), 
        .m_host_tlast(h10_rx_tlast), .m_host_valid(h10_rx_tvalid), .m_host_ready(h10_rx_tready),
        .m_noc_tdata(noc_tx_tdata[2]), .m_noc_tdest(noc_tx_tdest[2]), .m_noc_tid(noc_tx_tid[2]), 
        .m_noc_tlast(noc_tx_tlast[2]), .m_noc_valid(noc_tx_tvalid[2]), .m_noc_ready(noc_tx_tready[2]),
        .s_noc_tdata(noc_rx_tdata[2]), .s_noc_tdest(noc_rx_tdest[2]), .s_noc_tid(noc_rx_tid[2]), 
        .s_noc_tlast(noc_rx_tlast[2]), .s_noc_valid(noc_rx_tvalid[2]), .s_noc_ready(noc_rx_tready[2])
    );

    // [Index 3] Node 11
    gals_node_wrapper wrap_11 (
        .clk_noc(clk_noc), .clk_host(clk_h11), .rst_n(rst_n),
        .s_host_tdata(h11_tx_tdata), .s_host_tdest(h11_tx_tdest), .s_host_tid(h11_tx_tid), 
        .s_host_tlast(h11_tx_tlast), .s_host_valid(h11_tx_tvalid), .s_host_ready(h11_tx_tready),
        .m_host_tdata(h11_rx_tdata), .m_host_tdest(h11_rx_tdest), .m_host_tid(h11_rx_tid), 
        .m_host_tlast(h11_rx_tlast), .m_host_valid(h11_rx_tvalid), .m_host_ready(h11_rx_tready),
        .m_noc_tdata(noc_tx_tdata[3]), .m_noc_tdest(noc_tx_tdest[3]), .m_noc_tid(noc_tx_tid[3]), 
        .m_noc_tlast(noc_tx_tlast[3]), .m_noc_valid(noc_tx_tvalid[3]), .m_noc_ready(noc_tx_tready[3]),
        .s_noc_tdata(noc_rx_tdata[3]), .s_noc_tdest(noc_rx_tdest[3]), .s_noc_tid(noc_rx_tid[3]), 
        .s_noc_tlast(noc_rx_tlast[3]), .s_noc_valid(noc_rx_tvalid[3]), .s_noc_ready(noc_rx_tready[3])
    );

    // ==========================================
    // Hardware Performance Monitor
    // ==========================================
    `ifdef DEBUG_BUILD
        (* mark_debug = "true" *) logic [31:0] mon_flit_cnt;
        (* mark_debug = "true" *) logic [31:0] mon_pkt_cnt;
        (* mark_debug = "true" *) logic [31:0] mon_stall_cnt;
        (* mark_debug = "true" *) logic [31:0] mon_active_cnt;
    `endif

    // 2. เรียกใช้โมดูลและต่อสายขนานไปกับ AXI4-Stream ของ Host 00
    axis_perf_mon ingress_perf_mon (
        .clk(clk_h00),             // 🔴 แก้เป็น Clock ของ Host 00
        .rst_n(rst_n),             // ใช้ Global Reset ปกติ
        
        // 🔴 แอบดักฟังสายไฟที่วิ่งจาก Host 00 เข้าสู่เครือข่าย
        .valid(h00_tx_tvalid),     //
        .ready(h00_tx_tready[0]),  // ดักดูคิวของ VC0 (Video Stream)[cite: 2]
        .last(h00_tx_tlast),       //[cite: 2]
        
        .clear(1'b0),              // บังคับปิด Manual Clear ไปเลย
        .en(1'b1),                 // บังคับเปิดวงจรตลอดเวลา
        
        .flit_cnt(mon_flit_cnt),   
        .pkt_cnt(mon_pkt_cnt),     
        .stall_cnt(mon_stall_cnt), 
        .active_cnt(mon_active_cnt)
    );

endmodule
