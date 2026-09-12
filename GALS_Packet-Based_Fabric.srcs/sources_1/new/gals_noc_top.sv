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
    input  logic [1:0] h11_rx_tready, // 🟢 อัปเกรดเป็น 2 บิต

    // ---- ECC รวมของทั้ง NoC (sticky, โดเมน clk_noc)
    output logic       ecc_single_err,
    output logic       ecc_double_err,

    // ---- มีคนยิงปลายทางนอกกระดาน 2x2 (sticky, โดเมน clk_noc)
    output logic       dest_err,

    // ---- มีคนยิง tid ที่ไม่ใช่ one-hot (sticky, โดเมน clk_noc)
    output logic       tid_err
);

    logic [3:0] ecc_sbe, ecc_dbe;   // ธง ECC ต่อโหนด (0=00 1=01 2=10 3=11)
    logic [3:0] noc_dest_err;       // ธงปลายทางนอกกระดาน ต่อโหนดที่ยิงเข้ามา
    logic [3:0] noc_tid_err;        // ธง tid ไม่ใช่ one-hot ที่ขอบเมช (ต่อโหนด)
    logic [3:0] host_tid_err;       // ธง tid ไม่ใช่ one-hot ที่ขา host ของ wrapper

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
        .m_ready    (noc_rx_tready),
        .dest_err   (noc_dest_err),
        .tid_err    (noc_tid_err)
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
        .s_noc_tlast(noc_rx_tlast[0]), .s_noc_valid(noc_rx_tvalid[0]), .s_noc_ready(noc_rx_tready[0]),
        .ecc_single_err(ecc_sbe[0]), .ecc_double_err(ecc_dbe[0]), .host_tid_err(host_tid_err[0])
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
        .s_noc_tlast(noc_rx_tlast[1]), .s_noc_valid(noc_rx_tvalid[1]), .s_noc_ready(noc_rx_tready[1]),
        .ecc_single_err(ecc_sbe[1]), .ecc_double_err(ecc_dbe[1]), .host_tid_err(host_tid_err[1])
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
        .s_noc_tlast(noc_rx_tlast[2]), .s_noc_valid(noc_rx_tvalid[2]), .s_noc_ready(noc_rx_tready[2]),
        .ecc_single_err(ecc_sbe[2]), .ecc_double_err(ecc_dbe[2]), .host_tid_err(host_tid_err[2])
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
        .s_noc_tlast(noc_rx_tlast[3]), .s_noc_valid(noc_rx_tvalid[3]), .s_noc_ready(noc_rx_tready[3]),
        .ecc_single_err(ecc_sbe[3]), .ecc_double_err(ecc_dbe[3]), .host_tid_err(host_tid_err[3])
    );

    // ==========================================
    // Hardware Performance Monitor
    // ==========================================
    // ห้ามเอา `ifdef DEBUG_BUILD ครอบไว้อีก
    // ถ้า define หลุดไป (ซึ่งเคยเกิดมาแล้วตอน reset_run) ตัวแปรพวกนี้จะหายไปเงียบๆ
    // แล้ว SystemVerilog จะสร้าง implicit wire 1 บิตมาแทน พอร์ต 32 บิตของ
    // axis_perf_mon เลยถูกตัดเหลือบิตเดียวและถูกทิ้ง โดยขึ้นแค่ warning
    // ประกาศตรงๆ พร้อม dont_touch ปลอดภัยกว่าและ fanout ไม่เป็นศูนย์
    (* mark_debug = "true", dont_touch = "true" *) logic [31:0] mon_flit_cnt;
    (* mark_debug = "true", dont_touch = "true" *) logic [31:0] mon_pkt_cnt;
    (* mark_debug = "true", dont_touch = "true" *) logic [31:0] mon_stall_cnt;
    (* mark_debug = "true", dont_touch = "true" *) logic [31:0] mon_active_cnt;

    // ฝั่งขาเข้าของ node 00 — ทิศทางที่จะแออัดจริงตอนทดสอบ hot-spot
    (* mark_debug = "true", dont_touch = "true" *) logic [31:0] mon_rx_flit_cnt;
    (* mark_debug = "true", dont_touch = "true" *) logic [31:0] mon_rx_pkt_cnt;
    (* mark_debug = "true", dont_touch = "true" *) logic [31:0] mon_rx_stall_cnt;
    (* mark_debug = "true", dont_touch = "true" *) logic [31:0] mon_rx_active_cnt;

    // 2. เรียกใช้โมดูลและต่อสายขนานไปกับ AXI4-Stream ของ Host 00
    axis_perf_mon ingress_perf_mon (
        .clk(clk_h00),             // 🔴 แก้เป็น Clock ของ Host 00
        .rst_n(rst_n),             // ใช้ Global Reset ปกติ
        
        // 🔴 แอบดักฟังสายไฟที่วิ่งจาก Host 00 เข้าสู่เครือข่าย
        .valid(h00_tx_tvalid),
        // เดิมผูกไว้ที่ h00_tx_tready[0] คือดูแต่ ready ของ VC0
        // ทำให้ flit ที่วิ่งบน VC1 ถูกนับเป็น stall ทั้งที่จริงผ่านไปแล้ว
        // เงื่อนไขที่ถูกคือ "VC ที่ flit นี้ใช้ พร้อมหรือไม่" = |(tid & tready)
        // (ตรงกับที่ tb_noc_mesh_2x2_gals ใช้อยู่)
        .ready(|(h00_tx_tid & h00_tx_tready)),
        .last(h00_tx_tlast),

        .clear(1'b0),              // บังคับปิด Manual Clear ไปเลย
        .en(1'b1),                 // บังคับเปิดวงจรตลอดเวลา

        .flit_cnt(mon_flit_cnt),
        .pkt_cnt(mon_pkt_cnt),
        .stall_cnt(mon_stall_cnt),
        .active_cnt(mon_active_cnt)
    );

    // 3. ตัวที่สอง ดักฝั่งขาเข้าของ node 00
    //    ตอนทดสอบ hot-spot ตัว agent_00 จะเป็น sink อย่างเดียว ไม่ยิงออก
    //    monitor ตัวบนจึงอ่านได้ 0 ตลอด ต้องมีตัวนี้ถึงจะเห็น throughput ฝั่ง NoC
    axis_perf_mon egress_perf_mon (
        .clk(clk_h00),
        .rst_n(rst_n),

        .valid(h00_rx_tvalid),
        .ready(|(h00_rx_tid & h00_rx_tready)),
        .last(h00_rx_tlast),

        .clear(1'b0),
        .en(1'b1),

        .flit_cnt(mon_rx_flit_cnt),
        .pkt_cnt(mon_rx_pkt_cnt),
        .stall_cnt(mon_rx_stall_cnt),
        .active_cnt(mon_rx_active_cnt)
    );
    // =========================================================
    // ECC aggregation
    // ธง sticky จาก 4 โหนด (โดเมน clk_noc แล้วทั้งหมด) รวมเป็นตัวนับให้ ILA อ่าน
    // จนถึงตอนนี้ ecc_*_err ถูกปล่อยลอยมาตลอด ECC จึงตรวจเจอ error แล้วไม่มีใครรู้
    // ตัวนับต้อง mark_debug + dont_touch ไม่งั้นโดนกวาดทิ้งตอน synth (gotcha 1)
    // =========================================================
    (* mark_debug = "true", dont_touch = "true" *) logic [3:0]  ecc_sbe_node;
    (* mark_debug = "true", dont_touch = "true" *) logic [3:0]  ecc_dbe_node;
    (* mark_debug = "true", dont_touch = "true" *) logic [15:0] ecc_sbe_cnt;
    (* mark_debug = "true", dont_touch = "true" *) logic [15:0] ecc_dbe_cnt;

    assign ecc_sbe_node = ecc_sbe;
    assign ecc_dbe_node = ecc_dbe;

    // ธงเป็น level ที่ตั้งแล้วค้าง ตัวนับจึงนับ "ขอบขาขึ้น" = จำนวนโหนดที่เคยเจอ error
    // ไม่ใช่จำนวนครั้งที่เกิด error (จะได้ไม่นับซ้ำทุกไซเคิลจนล้น)
    logic [3:0] sbe_q, dbe_q;
    always_ff @(posedge clk_noc or negedge rst_n) begin
        if (!rst_n) begin
            sbe_q <= '0; dbe_q <= '0;
            ecc_sbe_cnt <= '0; ecc_dbe_cnt <= '0;
        end else begin
            sbe_q <= ecc_sbe;
            dbe_q <= ecc_dbe;
            for (int i = 0; i < 4; i++) begin
                if (ecc_sbe[i] && !sbe_q[i]) ecc_sbe_cnt <= ecc_sbe_cnt + 1'b1;
                if (ecc_dbe[i] && !dbe_q[i]) ecc_dbe_cnt <= ecc_dbe_cnt + 1'b1;
            end
        end
    end


    // =========================================================
    // Out-of-range tdest aggregation
    // เดินตามรูปแบบเดียวกับ ECC ข้างบนเป๊ะ: ธง sticky ต่อโหนด + ตัวนับขอบขาขึ้น
    // ต้อง mark_debug + dont_touch ไม่งั้นโดนกวาดทิ้งตอน synth (gotcha 1)
    //
    // ตัวนับนับ "จำนวนโหนดที่เคยยิงปลายทางผิด" ไม่ใช่จำนวน flit ที่ถูกทิ้ง
    // (ธงเป็น level ที่ตั้งแล้วค้าง เหมือน ECC) อ่านคู่กับ dest_err_node
    // จะรู้ว่าโหนดไหนเป็นต้นเหตุ
    // =========================================================
    (* mark_debug = "true", dont_touch = "true" *) logic [3:0]  dest_err_node;
    (* mark_debug = "true", dont_touch = "true" *) logic [15:0] dest_err_cnt;

    assign dest_err_node = noc_dest_err;

    logic [3:0] dest_err_q;
    always_ff @(posedge clk_noc or negedge rst_n) begin
        if (!rst_n) begin
            dest_err_q   <= '0;
            dest_err_cnt <= '0;
        end else begin
            dest_err_q <= noc_dest_err;
            for (int i = 0; i < 4; i++) begin
                if (noc_dest_err[i] && !dest_err_q[i]) dest_err_cnt <= dest_err_cnt + 1'b1;
            end
        end
    end


    // =========================================================
    // Non-one-hot tid aggregation
    // รูปแบบเดียวกับ ECC และ dest_err ทุกประการ: ธง sticky ต่อโหนด + ตัวนับขอบขาขึ้น
    // ต้อง mark_debug + dont_touch ไม่งั้นโดนกวาดทิ้งตอน synth (gotcha 1)
    // =========================================================
    (* mark_debug = "true", dont_touch = "true" *) logic [3:0]  tid_err_node;
    (* mark_debug = "true", dont_touch = "true" *) logic [15:0] tid_err_cnt;

    // ธงเดียวครอบทั้งสองจุดที่ tid เสียถูกจับได้:
    //   host_tid_err = ที่ขา host ของ wrapper (จุดที่ flit หายจริง)
    //   noc_tid_err  = ที่ขอบเมช (สัญญาของเมชเอง ปกติไม่มีทางดังเพราะ MUX ของ
    //                  wrapper สร้าง tid ให้ one-hot อยู่แล้ว)
    assign tid_err_node = noc_tid_err | host_tid_err;

    logic [3:0] tid_err_q;
    always_ff @(posedge clk_noc or negedge rst_n) begin
        if (!rst_n) begin
            tid_err_q   <= '0;
            tid_err_cnt <= '0;
        end else begin
            tid_err_q <= tid_err_node;
            for (int i = 0; i < 4; i++) begin
                if (tid_err_node[i] && !tid_err_q[i]) tid_err_cnt <= tid_err_cnt + 1'b1;
            end
        end
    end

    // ธงรวมที่ออกไปข้างนอกทั้งสี่ตัว (ecc_single_err / ecc_double_err / dest_err / tid_err)
    // ต้องผ่านรีจิสเตอร์ใน clk_noc ก่อน ไม่ใช่ OR แล้วส่งตรงเข้า sync_2stage ของ top
    // report_cdc (2026-09-12) จับเป็น CDC-10 Critical: "combinational logic before a
    // synchronizer" — LUT ที่ OR ธงหลายตัวอาจ glitch ตอนอินพุตหลายตัวเปลี่ยนพร้อมกัน
    // และ 2FF จะจับ glitch นั้นเป็นค่าจริง ธงพวกนี้ sticky จึงกลายเป็นสัญญาณเตือนหลอกได้
    // รีจิสเตอร์หนึ่งตัวปิดช่องนี้ ค่าใช้จ่าย = ช้าลงหนึ่งไซเคิลบนธงที่ตั้งแล้วค้างตลอดกาล
    logic ecc_single_err_q, ecc_double_err_q, dest_err_q_out, tid_err_q_out;
    always_ff @(posedge clk_noc or negedge rst_n) begin
        if (!rst_n) begin
            ecc_single_err_q <= 1'b0;
            ecc_double_err_q <= 1'b0;
            dest_err_q_out   <= 1'b0;
            tid_err_q_out    <= 1'b0;
        end else begin
            ecc_single_err_q <= |ecc_sbe;
            ecc_double_err_q <= |ecc_dbe;
            dest_err_q_out   <= |noc_dest_err;
            tid_err_q_out    <= |tid_err_node;
        end
    end
    assign ecc_single_err = ecc_single_err_q;
    assign dest_err       = dest_err_q_out;
    assign ecc_double_err = ecc_double_err_q;
    assign tid_err = tid_err_q_out;

endmodule
