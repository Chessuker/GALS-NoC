`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 07/16/2026 08:54:17 PM
// Design Name:
// Module Name: noc_stress_tester
// Project Name:
// Target Devices:
// Tool Versions:
// Description: ยิง traffic เต็มอัตราจากทั้ง 4 node พร้อมกัน แล้วเช็ค sequence
//              ที่ปลายทาง ตัวนับรายละเอียดอ่านผ่าน ILA ที่ตัว agent
//
//              ที่อยู่ปลายทาง tdest = {x[1:0], y[1:0]} โดย idx = y*2 + x
//                h00 = idx0 (x0,y0) -> 4'b0000
//                h01 = idx1 (x1,y0) -> 4'b0100
//                h10 = idx2 (x0,y1) -> 4'b0001
//                h11 = idx3 (x1,y1) -> 4'b0101
//
// Dependencies: traffic_node_agent, sync_2stage
//
// Revision:
// Revision 0.02 - ปรับให้ตรงกับ interface ใหม่ของ traffic_node_agent
//                 (multi-flit + VC + tid/tlast, สรุปผลด้วย done/err)
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////


module noc_stress_tester (
    input logic clk_h00, input logic clk_h01,
    input logic clk_h10, input logic clk_h11,
    input logic rst_n,

    // Node 00
    output logic [7:0] t00_tx_tdata, output logic [3:0] t00_tx_tdest, output logic [1:0] t00_tx_tid, output logic t00_tx_tlast, output logic t00_tx_tvalid, input logic [1:0] t00_tx_tready,
    input  logic [7:0] t00_rx_tdata, input  logic [3:0] t00_rx_tdest, input  logic [1:0] t00_rx_tid, input  logic t00_rx_tlast, input  logic t00_rx_tvalid, output logic [1:0] t00_rx_tready,
    // Node 01
    output logic [7:0] t01_tx_tdata, output logic [3:0] t01_tx_tdest, output logic [1:0] t01_tx_tid, output logic t01_tx_tlast, output logic t01_tx_tvalid, input logic [1:0] t01_tx_tready,
    input  logic [7:0] t01_rx_tdata, input  logic [3:0] t01_rx_tdest, input  logic [1:0] t01_rx_tid, input  logic t01_rx_tlast, input  logic t01_rx_tvalid, output logic [1:0] t01_rx_tready,
    // Node 10
    output logic [7:0] t10_tx_tdata, output logic [3:0] t10_tx_tdest, output logic [1:0] t10_tx_tid, output logic t10_tx_tlast, output logic t10_tx_tvalid, input logic [1:0] t10_tx_tready,
    input  logic [7:0] t10_rx_tdata, input  logic [3:0] t10_rx_tdest, input  logic [1:0] t10_rx_tid, input  logic t10_rx_tlast, input  logic t10_rx_tvalid, output logic [1:0] t10_rx_tready,
    // Node 11
    output logic [7:0] t11_tx_tdata, output logic [3:0] t11_tx_tdest, output logic [1:0] t11_tx_tid, output logic t11_tx_tlast, output logic t11_tx_tvalid, input logic [1:0] t11_tx_tready,
    input  logic [7:0] t11_rx_tdata, input  logic [3:0] t11_rx_tdest, input  logic [1:0] t11_rx_tid, input  logic t11_rx_tlast, input  logic t11_rx_tvalid, output logic [1:0] t11_rx_tready,

    // ---- สรุปผล ทุกเส้นถูก sync เข้ามาที่โดเมน clk_h00 แล้ว
    output logic pass_group1,   // 00 และ 11 จบ window โดยไม่มี error
    output logic pass_group2,   // 01 และ 10 จบ window โดยไม่มี error
    output logic any_fail
);

    logic d00, e00, d01, e01, d10, e10, d11, e11;

    // Node 00 ยิงไปหา 11
    traffic_node_agent #(.DEST_ID(4'b0101), .SRC_TAG(2'b00)) agent_00 (
        .clk(clk_h00), .rst_n(rst_n),
        .tx_tdata(t00_tx_tdata), .tx_tdest(t00_tx_tdest), .tx_tid(t00_tx_tid), .tx_tlast(t00_tx_tlast), .tx_tvalid(t00_tx_tvalid), .tx_tready(t00_tx_tready),
        .rx_tdata(t00_rx_tdata), .rx_tdest(t00_rx_tdest), .rx_tid(t00_rx_tid), .rx_tlast(t00_rx_tlast), .rx_tvalid(t00_rx_tvalid), .rx_tready(t00_rx_tready),
        .done(d00), .err(e00)
    );

    // Node 11 ยิงไปหา 00
    traffic_node_agent #(.DEST_ID(4'b0000), .SRC_TAG(2'b11)) agent_11 (
        .clk(clk_h11), .rst_n(rst_n),
        .tx_tdata(t11_tx_tdata), .tx_tdest(t11_tx_tdest), .tx_tid(t11_tx_tid), .tx_tlast(t11_tx_tlast), .tx_tvalid(t11_tx_tvalid), .tx_tready(t11_tx_tready),
        .rx_tdata(t11_rx_tdata), .rx_tdest(t11_rx_tdest), .rx_tid(t11_rx_tid), .rx_tlast(t11_rx_tlast), .rx_tvalid(t11_rx_tvalid), .rx_tready(t11_rx_tready),
        .done(d11), .err(e11)
    );

    // Node 01 ยิงไปหา 10
    traffic_node_agent #(.DEST_ID(4'b0001), .SRC_TAG(2'b01)) agent_01 (
        .clk(clk_h01), .rst_n(rst_n),
        .tx_tdata(t01_tx_tdata), .tx_tdest(t01_tx_tdest), .tx_tid(t01_tx_tid), .tx_tlast(t01_tx_tlast), .tx_tvalid(t01_tx_tvalid), .tx_tready(t01_tx_tready),
        .rx_tdata(t01_rx_tdata), .rx_tdest(t01_rx_tdest), .rx_tid(t01_rx_tid), .rx_tlast(t01_rx_tlast), .rx_tvalid(t01_rx_tvalid), .rx_tready(t01_rx_tready),
        .done(d01), .err(e01)
    );

    // Node 10 ยิงไปหา 01
    traffic_node_agent #(.DEST_ID(4'b0100), .SRC_TAG(2'b10)) agent_10 (
        .clk(clk_h10), .rst_n(rst_n),
        .tx_tdata(t10_tx_tdata), .tx_tdest(t10_tx_tdest), .tx_tid(t10_tx_tid), .tx_tlast(t10_tx_tlast), .tx_tvalid(t10_tx_tvalid), .tx_tready(t10_tx_tready),
        .rx_tdata(t10_rx_tdata), .rx_tdest(t10_rx_tdest), .rx_tid(t10_rx_tid), .rx_tlast(t10_rx_tlast), .rx_tvalid(t10_rx_tvalid), .rx_tready(t10_rx_tready),
        .done(d10), .err(e10)
    );

    // =========================================================
    // agent แต่ละตัวอยู่คนละโดเมนนาฬิกา ต้อง sync ก่อนเอามารวมกัน
    // เส้นพวกนี้เป็น flag ที่นิ่งยาว (แช่ค่าหลัง S_DONE) จึงใช้ 2FF ตรงๆ ได้
    // =========================================================
    logic [7:0] flags_raw, flags_s;
    assign flags_raw = {e11, d11, e10, d10, e01, d01, e00, d00};

    sync_2stage #(.WIDTH(8)) u_sync_flags (
        .clk(clk_h00), .rst(~rst_n), .d(flags_raw), .q(flags_s)
    );

    logic s_d00, s_e00, s_d01, s_e01, s_d10, s_e10, s_d11, s_e11;
    assign {s_e11, s_d11, s_e10, s_d10, s_e01, s_d01, s_e00, s_d00} = flags_s;

    assign pass_group1 = s_d00 & s_d11 & ~s_e00 & ~s_e11;
    assign pass_group2 = s_d01 & s_d10 & ~s_e01 & ~s_e10;
    assign any_fail    = s_e00 | s_e01 | s_e10 | s_e11;

endmodule
