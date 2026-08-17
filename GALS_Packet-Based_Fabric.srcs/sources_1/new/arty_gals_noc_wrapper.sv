`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/16/2026 08:36:26 PM
// Design Name: 
// Module Name: arty_gals_noc_wrapper
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


module arty_gals_noc_wrapper (
    input  logic clk_100mhz,
    input  logic rst_n_btn,
    
    // UART สำหรับเชื่อมต่อกับ PC
    input  logic uart_rxd,
    output logic uart_txd,

    output logic [3:0] led
);

    logic clk_noc, clk_h00, clk_h01, clk_h10, clk_h11;
    logic pll_locked;
    logic global_rst_n;

    clk_wiz_0 clk_gen (
        .clk_in1(clk_100mhz),
        .reset(~rst_n_btn),
        .clk_out1(clk_noc),
        .clk_out2(clk_h00),
        .clk_out3(clk_h01),
        .clk_out4(clk_h10),
        .clk_out5(clk_h11),
        .locked(pll_locked)
    );

    assign global_rst_n = rst_n_btn & pll_locked;

    // =========================================================
    // สายสัญญาณ NoC (อัปเดตให้รองรับ Multi-flit ครบทุก Node)
    // =========================================================
    logic [7:0] t00_tx_data; logic [3:0] t00_tx_dest; logic [1:0] t00_tx_tid; logic t00_tx_tlast; logic t00_tx_valid; logic [1:0] t00_tx_ready;
    logic [7:0] t00_rx_data; logic [3:0] t00_rx_dest; logic [1:0] t00_rx_tid; logic t00_rx_tlast; logic t00_rx_valid; logic [1:0] t00_rx_ready;

    logic [7:0] t01_tx_data; logic [3:0] t01_tx_dest; logic [1:0] t01_tx_tid; logic t01_tx_tlast; logic t01_tx_valid; logic [1:0] t01_tx_ready;
    logic [7:0] t01_rx_data; logic [3:0] t01_rx_dest; logic [1:0] t01_rx_tid; logic t01_rx_tlast; logic t01_rx_valid; logic [1:0] t01_rx_ready;

    logic [7:0] t10_tx_data; logic [3:0] t10_tx_dest; logic [1:0] t10_tx_tid; logic t10_tx_tlast; logic t10_tx_valid; logic [1:0] t10_tx_ready;
    logic [7:0] t10_rx_data; logic [3:0] t10_rx_dest; logic [1:0] t10_rx_tid; logic t10_rx_tlast; logic t10_rx_valid; logic [1:0] t10_rx_ready;

    logic [7:0] t11_tx_data; logic [3:0] t11_tx_dest; logic [1:0] t11_tx_tid; logic t11_tx_tlast; logic t11_tx_valid; logic [1:0] t11_tx_ready;
    logic [7:0] t11_rx_data; logic [3:0] t11_rx_dest; logic [1:0] t11_rx_tid; logic t11_rx_tlast; logic t11_rx_valid; logic [1:0] t11_rx_ready;

    // =========================================================
    // GALS NoC Instance
    // =========================================================
    gals_noc_top uut_noc_top (
        .clk_noc(clk_noc), .rst_n(global_rst_n),
        .clk_h00(clk_h00), .clk_h01(clk_h01), .clk_h10(clk_h10), .clk_h11(clk_h11),

        .h00_tx_tdata(t00_tx_data), .h00_tx_tdest(t00_tx_dest), .h00_tx_tid(t00_tx_tid), .h00_tx_tlast(t00_tx_tlast), .h00_tx_tvalid(t00_tx_valid), .h00_tx_tready(t00_tx_ready),
        .h00_rx_tdata(t00_rx_data), .h00_rx_tdest(t00_rx_dest), .h00_rx_tid(t00_rx_tid), .h00_rx_tlast(t00_rx_tlast), .h00_rx_tvalid(t00_rx_valid), .h00_rx_tready(t00_rx_ready),

        .h01_tx_tdata(t01_tx_data), .h01_tx_tdest(t01_tx_dest), .h01_tx_tid(t01_tx_tid), .h01_tx_tlast(t01_tx_tlast), .h01_tx_tvalid(t01_tx_valid), .h01_tx_tready(t01_tx_ready),
        .h01_rx_tdata(t01_rx_data), .h01_rx_tdest(t01_rx_dest), .h01_rx_tid(t01_rx_tid), .h01_rx_tlast(t01_rx_tlast), .h01_rx_tvalid(t01_rx_valid), .h01_rx_tready(t01_rx_ready),

        .h10_tx_tdata(t10_tx_data), .h10_tx_tdest(t10_tx_dest), .h10_tx_tid(t10_tx_tid), .h10_tx_tlast(t10_tx_tlast), .h10_tx_tvalid(t10_tx_valid), .h10_tx_tready(t10_tx_ready),
        .h10_rx_tdata(t10_rx_data), .h10_rx_tdest(t10_rx_dest), .h10_rx_tid(t10_rx_tid), .h10_rx_tlast(t10_rx_tlast), .h10_rx_tvalid(t10_rx_valid), .h10_rx_tready(t10_rx_ready),

        .h11_tx_tdata(t11_tx_data), .h11_tx_tdest(t11_tx_dest), .h11_tx_tid(t11_tx_tid), .h11_tx_tlast(t11_tx_tlast), .h11_tx_tvalid(t11_tx_valid), .h11_tx_tready(t11_tx_ready),
        .h11_rx_tdata(t11_rx_data), .h11_rx_tdest(t11_rx_dest), .h11_rx_tid(t11_rx_tid), .h11_rx_tlast(t11_rx_tlast), .h11_rx_tvalid(t11_rx_valid), .h11_rx_tready(t11_rx_ready)
    );

    // =========================================================
    // Node 00: UART Host (PC Gateway)
    // =========================================================
    uart_noc_host #(
        .CLK_FREQ(100_000_000), 
        .BAUD_RATE(3_000_000) 
    ) host_00 (
        .clk(clk_h00), .rst_n(global_rst_n),
        .uart_rxd(uart_rxd), .uart_txd(uart_txd),
        .tx_tdata(t00_tx_data), .tx_tdest(t00_tx_dest), .tx_tid(t00_tx_tid), .tx_tlast(t00_tx_tlast), .tx_tvalid(t00_tx_valid), .tx_tready(t00_tx_ready),
        .rx_tdata(t00_rx_data), .rx_tdest(t00_rx_dest), .rx_tid(t00_rx_tid), .rx_tlast(t00_rx_tlast), .rx_tvalid(t00_rx_valid), .rx_tready(t00_rx_ready)
    );

    // =========================================================
    // Node 01, 10, 11: Loopback Agents (Smart Consumers)
    // =========================================================
    loopback_node_agent echo_01 (
        .clk(clk_h01), .rst_n(global_rst_n),
        .rx_tdata(t01_rx_data), .rx_tdest(t01_rx_dest), .rx_tid(t01_rx_tid), .rx_tlast(t01_rx_tlast), .rx_tvalid(t01_rx_valid), .rx_tready(t01_rx_ready),
        .tx_tdata(t01_tx_data), .tx_tdest(t01_tx_dest), .tx_tid(t01_tx_tid), .tx_tlast(t01_tx_tlast), .tx_tvalid(t01_tx_valid), .tx_tready(t01_tx_ready)
    );

    loopback_node_agent echo_10 (
        .clk(clk_h10), .rst_n(global_rst_n),
        .rx_tdata(t10_rx_data), .rx_tdest(t10_rx_dest), .rx_tid(t10_rx_tid), .rx_tlast(t10_rx_tlast), .rx_tvalid(t10_rx_valid), .rx_tready(t10_rx_ready),
        .tx_tdata(t10_tx_data), .tx_tdest(t10_tx_dest), .tx_tid(t10_tx_tid), .tx_tlast(t10_tx_tlast), .tx_tvalid(t10_tx_valid), .tx_tready(t10_tx_ready)
    );

    loopback_node_agent echo_11 (
        .clk(clk_h11), .rst_n(global_rst_n),
        .rx_tdata(t11_rx_data), .rx_tdest(t11_rx_dest), .rx_tid(t11_rx_tid), .rx_tlast(t11_rx_tlast), .rx_tvalid(t11_rx_valid), .rx_tready(t11_rx_ready),
        .tx_tdata(t11_tx_data), .tx_tdest(t11_tx_dest), .tx_tid(t11_tx_tid), .tx_tlast(t11_tx_tlast), .tx_tvalid(t11_tx_valid), .tx_tready(t11_tx_ready)
    );

    // =========================================================
    // LED Status Mapping
    // =========================================================
    logic [26:0] heartbeat_cnt;
    always_ff @(posedge clk_h00 or negedge global_rst_n) begin
        if (!global_rst_n) heartbeat_cnt <= '0;
        else heartbeat_cnt <= heartbeat_cnt + 1'b1;
    end

    assign led[0] = heartbeat_cnt[26];
    assign led[1] = ~uart_rxd; // ไฟกระพริบเมื่อ PC ส่งข้อมูลเข้า NoC
    assign led[2] = ~uart_txd; // ไฟกระพริบเมื่อ NoC ส่งข้อมูลกลับหา PC
    
    // ไฟกระพริบเมื่อ Node ภายในกำลังสะท้อนข้อมูลกลับ (NoC Internal Activity)
    assign led[3] = (t01_tx_valid | t10_tx_valid | t11_tx_valid); 
    
endmodule
