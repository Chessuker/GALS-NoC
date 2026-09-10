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


module arty_stress_top #(
    // 0 = permutation (ผลอ้างอิงเดิม 285.8 MB/s / link util 89.3%)
    // 1 = hot-spot ยิงรวมเข้า node 00 เพื่อบีบให้ arbiter ทำงานจริง
    // เปลี่ยนตรงนี้แล้ว re-synthesize หรือ override ผ่าน
    //   set_property generic {PATTERN=1} [get_filesets sources_1]
    parameter int PATTERN = 0,

    // 0 = VC0 อย่างเดียว, 1 = VC1 อย่างเดียว, 2 = สลับทุกแพ็กเกจ (ค่าเดิม)
    parameter int VC_MODE = 2
)(
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
    // ประกาศไว้ *ก่อน* instance ที่ขับมัน: ถ้าประกาศทีหลัง สายพวกนี้จะถูก
    // implicit-declare ตอนต่อพอร์ตก่อน แล้ว xvlog ฟ้อง "already implicitly
    // declared" (Vivado synth ปล่อยผ่าน แต่ตัว simulator ไม่ยอม)
    // ของเดิม ecc_sbe_noc/ecc_dbe_noc ก็ติดปัญหานี้อยู่แล้ว ย้ายขึ้นมาพร้อมกัน
    logic ecc_sbe_noc, ecc_dbe_noc;   // sticky, โดเมน clk_noc
    logic dest_err_noc;               // sticky, โดเมน clk_noc — ปลายทางนอกกระดาน
    logic tid_err_noc;                // sticky, โดเมน clk_noc — tid ไม่ใช่ one-hot

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
        .h11_rx_tdata(t11_rx_tdata), .h11_rx_tdest(t11_rx_tdest), .h11_rx_tid(t11_rx_tid), .h11_rx_tlast(t11_rx_tlast), .h11_rx_tvalid(t11_rx_tvalid), .h11_rx_tready(t11_rx_tready),

        .ecc_single_err(ecc_sbe_noc), .ecc_double_err(ecc_dbe_noc),
        .dest_err(dest_err_noc), .tid_err(tid_err_noc)
    );

    // =========================================================
    // Traffic agents ทั้ง 4 node — ตัวนี้แหละที่มี mark_debug ให้ ILA จับ
    // =========================================================
    logic pass_g1, pass_g2, any_fail;

    noc_stress_tester #(.PATTERN(PATTERN), .VC_MODE(VC_MODE)) u_stress (
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

    // =========================================================
    // ECC : ธง sticky จาก NoC (โดเมน clk_noc) ข้ามมาที่ clk_h00 ก่อนใช้กับ LED
    // ตั้งแล้วไม่กลับ จึงใช้ 2FF ได้ (เหตุผลเดียวกับธง done/err)
    // =========================================================
    logic [3:0] ecc_flags_sync;
    sync_2stage #(.WIDTH(4)) u_ecc_led_sync (
        .clk(clk_h00), .rst(~global_rst_n),
        .d({tid_err_noc, dest_err_noc, ecc_dbe_noc, ecc_sbe_noc}),
        .q(ecc_flags_sync)
    );
    logic ecc_sbe_s, ecc_dbe_s, dest_err_s, tid_err_s;
    assign ecc_sbe_s  = ecc_flags_sync[0];
    assign ecc_dbe_s  = ecc_flags_sync[1];
    assign dest_err_s = ecc_flags_sync[2];
    assign tid_err_s  = ecc_flags_sync[3];

    // PATTERN 0 : led1 = คู่ 00<->11 ผ่าน, led2 = คู่ 01<->10 ผ่าน
    // PATTERN 1 : led1 = ทุก agent จบ window, led2 = จบครบและ node 00 ไม่เจอ error
    //
    // double-bit ECC error = ข้อมูลเสียที่ซ่อมไม่ได้ ต้องนับเป็นสอบตกเสมอ
    // ไฟผ่านจึงต้องดับด้วย ไม่ใช่แค่ติดไฟแดงเพิ่ม — บทเรียนเดียวกับ liveness:
    // ไฟเขียวที่ยังติดตอนข้อมูลพัง คือไฟเขียวที่โกหก
    //
    // ปลายทางนอกกระดานก็นับเป็นสอบตกด้วยเหตุผลเดียวกัน: flit ถูกทิ้งไปแล้ว
    // แพกเกจนั้นไม่มีทางไปถึงใคร ไฟผ่านที่ยังติดอยู่ก็คือไฟเขียวที่โกหกอีกแบบ
    assign led[0] = heartbeat_cnt[26];   // ยังมีชีวิต
    assign led[1] = pass_g1  & ~ecc_dbe_s & ~dest_err_s & ~tid_err_s;
    assign led[2] = pass_g2  & ~ecc_dbe_s & ~dest_err_s & ~tid_err_s;
    assign led[3] = any_fail | ecc_dbe_s | dest_err_s | tid_err_s;

endmodule
