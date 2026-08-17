`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company:
// Engineer:
//
// Create Date: 08/05/2026
// Design Name:
// Module Name: arty_stress_top
// Project Name:
// Target Devices: Arty A7-100T (xc7a100tcsg324-1)
// Tool Versions:
// Description: Top-level สำหรับ "stress build" โดยเฉพาะ
//              clk_wiz_0 + gals_noc_top + noc_stress_tester
//
//              ตัวนี้อยู่คู่กับ arty_gals_noc_wrapper (UART build) ได้
//              สลับไปมาด้วยการเปลี่ยน top module ของ project อย่างเดียว
//
//              ชื่อ port เหมือน arty_gals_noc_wrapper ทุกตัว เพื่อให้ arty.xdc
//              ใช้ได้โดยไม่ต้องแก้ (uart_rxd/uart_txd คงไว้แต่ไม่ได้ใช้งาน)
//
// Dependencies: clk_wiz_0, gals_noc_top, noc_stress_tester
//
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
//
//////////////////////////////////////////////////////////////////////////////////


module arty_stress_top (
    input  logic clk_100mhz,
    input  logic rst_n_btn,

    // คงไว้ให้ตรงกับ arty.xdc — build นี้ไม่ได้ใช้ UART
    input  logic uart_rxd,
    output logic uart_txd,

    output logic [3:0] led
);

    logic clk_noc, clk_h00, clk_h01, clk_h10, clk_h11;
    logic pll_locked;
    logic global_rst_n;

    // ปุ่ม RESET ต้องไม่ไปแตะ MMCM
    // ถ้าผูก .reset(~rst_n_btn) ไว้ พอกดปุ่มที clock ดับทั้ง 5 เส้น
    // dbg_hub กับ ILA ใช้ clock พวกนี้อยู่ capture เลยพังตาม
    // MMCM self-start ตอน configuration อยู่แล้ว ตรึง reset ไว้ที่ 0 ได้เลย
    clk_wiz_0 clk_gen (
        .clk_in1(clk_100mhz),
        .reset(1'b0),
        .clk_out1(clk_noc),
        .clk_out2(clk_h00),
        .clk_out3(clk_h01),
        .clk_out4(clk_h10),
        .clk_out5(clk_h11),
        .locked(pll_locked)
    );

    assign global_rst_n = rst_n_btn & pll_locked;

    // UART ไม่ได้ใช้ใน build นี้ ตรึงไว้ที่ idle
    assign uart_txd = 1'b1;

    // =========================================================
    // สายสัญญาณ NoC
    // =========================================================
    logic [7:0] t00_tx_tdata; logic [3:0] t00_tx_tdest; logic [1:0] t00_tx_tid; logic t00_tx_tlast; logic t00_tx_tvalid; logic [1:0] t00_tx_tready;
    logic [7:0] t00_rx_tdata; logic [3:0] t00_rx_tdest; logic [1:0] t00_rx_tid; logic t00_rx_tlast; logic t00_rx_tvalid; logic [1:0] t00_rx_tready;

    logic [7:0] t01_tx_tdata; logic [3:0] t01_tx_tdest; logic [1:0] t01_tx_tid; logic t01_tx_tlast; logic t01_tx_tvalid; logic [1:0] t01_tx_tready;
    logic [7:0] t01_rx_tdata; logic [3:0] t01_rx_tdest; logic [1:0] t01_rx_tid; logic t01_rx_tlast; logic t01_rx_tvalid; logic [1:0] t01_rx_tready;

    logic [7:0] t10_tx_tdata; logic [3:0] t10_tx_tdest; logic [1:0] t10_tx_tid; logic t10_tx_tlast; logic t10_tx_tvalid; logic [1:0] t10_tx_tready;
    logic [7:0] t10_rx_tdata; logic [3:0] t10_rx_tdest; logic [1:0] t10_rx_tid; logic t10_rx_tlast; logic t10_rx_tvalid; logic [1:0] t10_rx_tready;

    logic [7:0] t11_tx_tdata; logic [3:0] t11_tx_tdest; logic [1:0] t11_tx_tid; logic t11_tx_tlast; logic t11_tx_tvalid; logic [1:0] t11_tx_tready;
    logic [7:0] t11_rx_tdata; logic [3:0] t11_rx_tdest; logic [1:0] t11_rx_tid; logic t11_rx_tlast; logic t11_rx_tvalid; logic [1:0] t11_rx_tready;

    // =========================================================
    // GALS NoC
    // =========================================================
    gals_noc_top uut_noc_top (
        .clk_noc(clk_noc), .rst_n(global_rst_n),
        .clk_h00(clk_h00), .clk_h01(clk_h01), .clk_h10(clk_h10), .clk_h11(clk_h11),

        .h00_tx_tdata(t00_tx_tdata), .h00_tx_tdest(t00_tx_tdest), .h00_tx_tid(t00_tx_tid), .h00_tx_tlast(t00_tx_tlast), .h00_tx_tvalid(t00_tx_tvalid), .h00_tx_tready(t00_tx_tready),
        .h00_rx_tdata(t00_rx_tdata), .h00_rx_tdest(t00_rx_tdest), .h00_rx_tid(t00_rx_tid), .h00_rx_tlast(t00_rx_tlast), .h00_rx_tvalid(t00_rx_tvalid), .h00_rx_tready(t00_rx_tready),

        .h01_tx_tdata(t01_tx_tdata), .h01_tx_tdest(t01_tx_tdest), .h01_tx_tid(t01_tx_tid), .h01_tx_tlast(t01_tx_tlast), .h01_tx_tvalid(t01_tx_tvalid), .h01_tx_tready(t01_tx_tready),
        .h01_rx_tdata(t01_rx_tdata), .h01_rx_tdest(t01_rx_tdest), .h01_rx_tid(t01_rx_tid), .h01_rx_tlast(t01_rx_tlast), .h01_rx_tvalid(t01_rx_tvalid), .h01_rx_tready(t01_rx_tready),

        .h10_tx_tdata(t10_tx_tdata), .h10_tx_tdest(t10_tx_tdest), .h10_tx_tid(t10_tx_tid), .h10_tx_tlast(t10_tx_tlast), .h10_tx_tvalid(t10_tx_tvalid), .h10_tx_tready(t10_tx_tready),
        .h10_rx_tdata(t10_rx_tdata), .h10_rx_tdest(t10_rx_tdest), .h10_rx_tid(t10_rx_tid), .h10_rx_tlast(t10_rx_tlast), .h10_rx_tvalid(t10_rx_tvalid), .h10_rx_tready(t10_rx_tready),

        .h11_tx_tdata(t11_tx_tdata), .h11_tx_tdest(t11_tx_tdest), .h11_tx_tid(t11_tx_tid), .h11_tx_tlast(t11_tx_tlast), .h11_tx_tvalid(t11_tx_tvalid), .h11_tx_tready(t11_tx_tready),
        .h11_rx_tdata(t11_rx_tdata), .h11_rx_tdest(t11_rx_tdest), .h11_rx_tid(t11_rx_tid), .h11_rx_tlast(t11_rx_tlast), .h11_rx_tvalid(t11_rx_tvalid), .h11_rx_tready(t11_rx_tready)
    );

    // =========================================================
    // Traffic agents ทั้ง 4 node — ตัวนี้แหละที่มี mark_debug ให้ ILA จับ
    // =========================================================
    logic pass_g1, pass_g2, any_fail;

    noc_stress_tester u_stress (
        .clk_h00(clk_h00), .clk_h01(clk_h01), .clk_h10(clk_h10), .clk_h11(clk_h11),
        .rst_n(global_rst_n),

        .t00_tx_tdata(t00_tx_tdata), .t00_tx_tdest(t00_tx_tdest), .t00_tx_tid(t00_tx_tid), .t00_tx_tlast(t00_tx_tlast), .t00_tx_tvalid(t00_tx_tvalid), .t00_tx_tready(t00_tx_tready),
        .t00_rx_tdata(t00_rx_tdata), .t00_rx_tdest(t00_rx_tdest), .t00_rx_tid(t00_rx_tid), .t00_rx_tlast(t00_rx_tlast), .t00_rx_tvalid(t00_rx_tvalid), .t00_rx_tready(t00_rx_tready),

        .t01_tx_tdata(t01_tx_tdata), .t01_tx_tdest(t01_tx_tdest), .t01_tx_tid(t01_tx_tid), .t01_tx_tlast(t01_tx_tlast), .t01_tx_tvalid(t01_tx_tvalid), .t01_tx_tready(t01_tx_tready),
        .t01_rx_tdata(t01_rx_tdata), .t01_rx_tdest(t01_rx_tdest), .t01_rx_tid(t01_rx_tid), .t01_rx_tlast(t01_rx_tlast), .t01_rx_tvalid(t01_rx_tvalid), .t01_rx_tready(t01_rx_tready),

        .t10_tx_tdata(t10_tx_tdata), .t10_tx_tdest(t10_tx_tdest), .t10_tx_tid(t10_tx_tid), .t10_tx_tlast(t10_tx_tlast), .t10_tx_tvalid(t10_tx_tvalid), .t10_tx_tready(t10_tx_tready),
        .t10_rx_tdata(t10_rx_tdata), .t10_rx_tdest(t10_rx_tdest), .t10_rx_tid(t10_rx_tid), .t10_rx_tlast(t10_rx_tlast), .t10_rx_tvalid(t10_rx_tvalid), .t10_rx_tready(t10_rx_tready),

        .t11_tx_tdata(t11_tx_tdata), .t11_tx_tdest(t11_tx_tdest), .t11_tx_tid(t11_tx_tid), .t11_tx_tlast(t11_tx_tlast), .t11_tx_tvalid(t11_tx_tvalid), .t11_tx_tready(t11_tx_tready),
        .t11_rx_tdata(t11_rx_tdata), .t11_rx_tdest(t11_rx_tdest), .t11_rx_tid(t11_rx_tid), .t11_rx_tlast(t11_rx_tlast), .t11_rx_tvalid(t11_rx_tvalid), .t11_rx_tready(t11_rx_tready),

        .pass_group1(pass_g1), .pass_group2(pass_g2), .any_fail(any_fail)
    );

    // =========================================================
    // LED Status
    // =========================================================
    logic [26:0] heartbeat_cnt;
    always_ff @(posedge clk_h00 or negedge global_rst_n) begin
        if (!global_rst_n) heartbeat_cnt <= '0;
        else               heartbeat_cnt <= heartbeat_cnt + 1'b1;
    end

    assign led[0] = heartbeat_cnt[26];   // ยังมีชีวิต
    assign led[1] = pass_g1;             // คู่ 00 <-> 11 ผ่าน
    assign led[2] = pass_g2;             // คู่ 01 <-> 10 ผ่าน
    assign led[3] = any_fail;            // เจอ sequence error

endmodule
