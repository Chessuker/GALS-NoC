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
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module noc_stress_tester (
    input logic clk_h00, input logic clk_h01, 
    input logic clk_h10, input logic clk_h11, 
    input logic rst_n,
    
    // Node 00
    output logic [7:0] t00_tx_data, output logic [3:0] t00_tx_dest, output logic t00_tx_valid, input logic [1:0] t00_tx_ready,
    input  logic [7:0] t00_rx_data, input  logic t00_rx_valid, output logic [1:0] t00_rx_ready,
    // Node 01
    output logic [7:0] t01_tx_data, output logic [3:0] t01_tx_dest, output logic t01_tx_valid, input logic [1:0] t01_tx_ready,
    input  logic [7:0] t01_rx_data, input  logic t01_rx_valid, output logic [1:0] t01_rx_ready,
    // Node 10
    output logic [7:0] t10_tx_data, output logic [3:0] t10_tx_dest, output logic t10_tx_valid, input logic [1:0] t10_tx_ready,
    input  logic [7:0] t10_rx_data, input  logic t10_rx_valid, output logic [1:0] t10_rx_ready,
    // Node 11
    output logic [7:0] t11_tx_data, output logic [3:0] t11_tx_dest, output logic t11_tx_valid, input logic [1:0] t11_tx_ready,
    input  logic [7:0] t11_rx_data, input  logic t11_rx_valid, output logic [1:0] t11_rx_ready,
    
    output logic pass_group1, // 00 และ 11 ผ่าน
    output logic pass_group2, // 01 และ 10 ผ่าน
    output logic any_fail
);
    logic p00, f00, p01, f01, p10, f10, p11, f11;

    // Node 00 ยิงไป 11 (Payload 0xAA, คาดหวังรับกลับ 0x55)
    traffic_node_agent #(.DEST_ID(4'b0101), .PAYLOAD(8'hAA)) agent_00 (
        .clk(clk_h00), .rst_n(rst_n),
        .tx_tdata(t00_tx_data), .tx_tdest(t00_tx_dest), .tx_tvalid(t00_tx_valid), .tx_tready(t00_tx_ready),
        .rx_tdata(t00_rx_data), .rx_tvalid(t00_rx_valid), .rx_tready(t00_rx_ready), .pass(p00), .fail(f00)
    );

    // Node 11 ยิงไป 00 (Payload 0x55, คาดหวังรับกลับ 0xAA)
    traffic_node_agent #(.DEST_ID(4'b0000), .PAYLOAD(8'h55)) agent_11 (
        .clk(clk_h11), .rst_n(rst_n),
        .tx_tdata(t11_tx_data), .tx_tdest(t11_tx_dest), .tx_tvalid(t11_tx_valid), .tx_tready(t11_tx_ready),
        .rx_tdata(t11_rx_data), .rx_tvalid(t11_rx_valid), .rx_tready(t11_rx_ready), .pass(p11), .fail(f11)
    );

    // Node 01 ยิงไป 10 (Payload 0xCC, คาดหวังรับกลับ 0x33)
    traffic_node_agent #(.DEST_ID(4'b0001), .PAYLOAD(8'hCC)) agent_01 (
        .clk(clk_h01), .rst_n(rst_n),
        .tx_tdata(t01_tx_data), .tx_tdest(t01_tx_dest), .tx_tvalid(t01_tx_valid), .tx_tready(t01_tx_ready),
        .rx_tdata(t01_rx_data), .rx_tvalid(t01_rx_valid), .rx_tready(t01_rx_ready), .pass(p01), .fail(f01)
    );

    // Node 10 ยิงไป 01 (Payload 0x33, คาดหวังรับกลับ 0xCC)
    traffic_node_agent #(.DEST_ID(4'b0100), .PAYLOAD(8'h33)) agent_10 (
        .clk(clk_h10), .rst_n(rst_n),
        .tx_tdata(t10_tx_data), .tx_tdest(t10_tx_dest), .tx_tvalid(t10_tx_valid), .tx_tready(t10_tx_ready),
        .rx_tdata(t10_rx_data), .rx_tvalid(t10_rx_valid), .rx_tready(t10_rx_ready), .pass(p10), .fail(f10)
    );

    assign pass_group1 = p00 & p11;
    assign pass_group2 = p01 & p10;
    assign any_fail    = f00 | f01 | f10 | f11;

endmodule
