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


module noc_stress_tester #(
    // PATTERN = 0 : permutation (00<->11, 01<->10)
    //               ทุก flow ใช้ลิงก์คนละเส้น ไม่มีการแย่ง output port เลย
    //               วัด GALS throughput ล้วนๆ (ผลอ้างอิง: 285.8 MB/s, link util 89.3%)
    //
    // PATTERN = 1 : hot-spot ยิงรวมเข้า node 00 จาก 01/10/11 พร้อมกัน
    //               agent_00 ปิดขาส่ง เป็น sink อย่างเดียว
    //               บังคับให้เกิดการแย่ง output port จริง 2 ชั้น:
    //                 router idx2 : local ของ agent_10 ปะทะ transit จาก idx3
    //                 router idx0 : ขา EAST (agent_01) ปะทะขา NORTH (agent_10+11)
    //               เป็นเทสต์ที่ตรงกับ sim Test 4 (Multi-Port Contention)
    parameter int PATTERN = 0,

    // ส่งต่อให้ traffic_node_agent ทุกตัว
    //   0 = VC0 อย่างเดียว   1 = VC1 อย่างเดียว   2 = สลับทุกแพ็กเกจ (ค่าเดิม)
    // ใช้ทดสอบว่าการสลับ VC คือสาเหตุที่ hot-spot บนบอร์ดได้แค่ 57.5%
    // (ใน sim การสลับ VC ทำให้ NoC ค้าง ส่วน VC0 อย่างเดียวได้ 95-99%)
    parameter int VC_MODE = 2,

    // ---- เวลาของ agent ส่งผ่านลงไปทั้ง 4 ตัว
    // ค่า default = ค่าเดิมของ traffic_node_agent ของบนบอร์ดจึงไม่เปลี่ยน
    // มีไว้ให้ testbench ย่อ window ลงได้ ไม่งั้น 2^24 cycle x 4 โดเมน
    // จำลองไม่ไหว (0.2 วินาที) โครงสร้าง stress นี้จึงไม่เคยถูกจำลองเลย
    parameter int WINDOW_LOG = 24,
    parameter int WARMUP_LOG = 10,
    parameter int DRAIN_LOG  = 12,
    parameter int STUCK_LOG  = 16,
    parameter int GAP_W      = 24
)(
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

    // ---- เลือกปลายทางตาม PATTERN
    //      SRC_TAG ต้องไม่ซ้ำกันทั้ง 4 ตัวเสมอ ไม่งั้นตัวเช็ค sequence ที่ปลายทาง
    //      (exp_seq[rx_src][rx_vc]) จะปนกันแล้วนับ error มั่ว
    localparam logic [3:0] DEST_00 = 4'b0101;                        // -> h11 (ใช้เฉพาะ PATTERN 0)
    localparam logic [3:0] DEST_01 = (PATTERN == 1) ? 4'b0000        // -> h00
                                                    : 4'b0001;       // -> h10
    localparam logic [3:0] DEST_10 = (PATTERN == 1) ? 4'b0000        // -> h00
                                                    : 4'b0100;       // -> h01
    localparam logic [3:0] DEST_11 = 4'b0000;                        // -> h00 ทั้งสอง pattern

    // PATTERN 1: node 00 เป็นเป้า ต้องปิดขาส่งของมัน ไม่งั้นจะยิงใส่ตัวเอง
    localparam bit TXEN_00 = (PATTERN == 1) ? 1'b0 : 1'b1;

    // Node 00 -> h11 (PATTERN 0) / sink อย่างเดียว (PATTERN 1)
    traffic_node_agent #(.DEST_ID(DEST_00), .SRC_TAG(2'b00), .TX_EN(TXEN_00), .VC_MODE(VC_MODE),
        .WINDOW_LOG(WINDOW_LOG), .WARMUP_LOG(WARMUP_LOG), .DRAIN_LOG(DRAIN_LOG),
        .STUCK_LOG(STUCK_LOG), .GAP_W(GAP_W)) agent_00 (
        .clk(clk_h00), .rst_n(rst_n),
        .tx_tdata(t00_tx_tdata), .tx_tdest(t00_tx_tdest), .tx_tid(t00_tx_tid), .tx_tlast(t00_tx_tlast), .tx_tvalid(t00_tx_tvalid), .tx_tready(t00_tx_tready),
        .rx_tdata(t00_rx_tdata), .rx_tdest(t00_rx_tdest), .rx_tid(t00_rx_tid), .rx_tlast(t00_rx_tlast), .rx_tvalid(t00_rx_tvalid), .rx_tready(t00_rx_tready),
        .done(d00), .err(e00)
    );

    // Node 11 -> h00 (ทั้งสอง pattern)
    traffic_node_agent #(.DEST_ID(DEST_11), .SRC_TAG(2'b11), .VC_MODE(VC_MODE),
        .WINDOW_LOG(WINDOW_LOG), .WARMUP_LOG(WARMUP_LOG), .DRAIN_LOG(DRAIN_LOG),
        .STUCK_LOG(STUCK_LOG), .GAP_W(GAP_W)) agent_11 (
        .clk(clk_h11), .rst_n(rst_n),
        .tx_tdata(t11_tx_tdata), .tx_tdest(t11_tx_tdest), .tx_tid(t11_tx_tid), .tx_tlast(t11_tx_tlast), .tx_tvalid(t11_tx_tvalid), .tx_tready(t11_tx_tready),
        .rx_tdata(t11_rx_tdata), .rx_tdest(t11_rx_tdest), .rx_tid(t11_rx_tid), .rx_tlast(t11_rx_tlast), .rx_tvalid(t11_rx_tvalid), .rx_tready(t11_rx_tready),
        .done(d11), .err(e11)
    );

    // Node 01 -> h10 (PATTERN 0) / h00 (PATTERN 1)
    traffic_node_agent #(.DEST_ID(DEST_01), .SRC_TAG(2'b01), .VC_MODE(VC_MODE),
        .WINDOW_LOG(WINDOW_LOG), .WARMUP_LOG(WARMUP_LOG), .DRAIN_LOG(DRAIN_LOG),
        .STUCK_LOG(STUCK_LOG), .GAP_W(GAP_W)) agent_01 (
        .clk(clk_h01), .rst_n(rst_n),
        .tx_tdata(t01_tx_tdata), .tx_tdest(t01_tx_tdest), .tx_tid(t01_tx_tid), .tx_tlast(t01_tx_tlast), .tx_tvalid(t01_tx_tvalid), .tx_tready(t01_tx_tready),
        .rx_tdata(t01_rx_tdata), .rx_tdest(t01_rx_tdest), .rx_tid(t01_rx_tid), .rx_tlast(t01_rx_tlast), .rx_tvalid(t01_rx_tvalid), .rx_tready(t01_rx_tready),
        .done(d01), .err(e01)
    );

    // Node 10 -> h01 (PATTERN 0) / h00 (PATTERN 1)
    traffic_node_agent #(.DEST_ID(DEST_10), .SRC_TAG(2'b10), .VC_MODE(VC_MODE),
        .WINDOW_LOG(WINDOW_LOG), .WARMUP_LOG(WARMUP_LOG), .DRAIN_LOG(DRAIN_LOG),
        .STUCK_LOG(STUCK_LOG), .GAP_W(GAP_W)) agent_10 (
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

    // ความหมายของไฟต้องเปลี่ยนตาม pattern ด้วย
    // PATTERN 1 ไม่มีใครส่งไปหา 01/10/11 เลย ตัว err ของสามตัวนั้นจึงเป็น 0
    // โดยปริยาย ถ้ายังใช้สูตรเดิม pass_group2 จะติดฟรีทั้งที่ไม่ได้พิสูจน์อะไร
    generate
        if (PATTERN == 1) begin : G_HOTSPOT
            // node 00 เป็นตัวเดียวที่รับของ จึงเป็นตัวเดียวที่ตัดสิน error ได้
            assign pass_group1 = s_d00 & s_d01 & s_d10 & s_d11;            // ครบ window แล้ว
            assign pass_group2 = s_d00 & s_d01 & s_d10 & s_d11 & ~s_e00;   // ครบ + ไม่มี error
            assign any_fail    = s_e00;
        end else begin : G_PERMUTATION
            assign pass_group1 = s_d00 & s_d11 & ~s_e00 & ~s_e11;
            assign pass_group2 = s_d01 & s_d10 & ~s_e01 & ~s_e10;
            assign any_fail    = s_e00 | s_e01 | s_e10 | s_e11;
        end
    endgenerate

endmodule
