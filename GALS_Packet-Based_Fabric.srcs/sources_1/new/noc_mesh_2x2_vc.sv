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
    input  logic [3:0][NUM_VCS-1:0] m_ready,

    // ---- ปลายทางนอกกระดาน: sticky ต่อโหนดที่ยิงเข้ามา (โดเมน clk เดียวกับเมช)
    output logic [3:0]              dest_err,

    // ---- tid ไม่ใช่ one-hot: sticky ต่อโหนดที่ยิงเข้ามา
    output logic [3:0]              tid_err
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

    // สถานะตัวปิดแพกเกจค้างต่อโหนด (หัวข้อ 2.2) ยกออกมาระดับโมดูลให้บล็อก FORMAL อ้างได้
    logic [3:0]              ing_closing;
    logic [3:0][NUM_VCS-1:0] ing_pkt_open;
    logic [3:0][NUM_VCS-1:0] ing_close_pend;
    logic [3:0][NUM_VCS-1:0] ing_close_acc;

    // =================================================================
    // 1. วาง Router 4 ตัว ลงบนกระดาน (Instantiation)
    // =================================================================
    genvar x, y;
    generate
        for (y = 0; y < 2; y++) begin : ROW
            for (x = 0; x < 2; x++) begin : COL
                localparam int idx = y * 2 + x;
                
                router_5port_mesh_vc #(
                    .MY_X(x), .MY_Y(y), .DATA_W(DATA_W), .CORD_W(CORD_W), .NUM_VCS(NUM_VCS), .DEPTH(DEPTH)
                ) router (
                    .clk(clk), .rst_n(rst_n),
                    .s_valid(r_valid[idx]), .s_tlast(r_last[idx]), .s_tdest(r_dst[idx]), .s_tdata(r_dat[idx]), .s_tid(r_tid[idx]), .s_ready(r_rdy[idx]),
                    .m_valid(m_valid_wire[idx]), .m_tlast(m_last_wire[idx]), .m_tdest(m_dst_wire[idx]), .m_tdata(m_dat_wire[idx]), .m_tid(m_tid_wire[idx]), .m_ready(m_rdy_wire[idx])
                );
            end
        end
    endgenerate

    // =================================================================
    // 0. ตรวจปลายทางก่อนปล่อยเข้าเมช
    //
    // s_tdest กว้าง 4 บิต (x=[3:2], y=[1:0]) รับค่าได้ถึง 3 ต่อแกน แต่กระดานมี 2x2
    // ถ้าปล่อย flit ที่ x=2/3 หรือ y=2/3 เข้าไป ตัวถอด XY จะเห็น dx > MY_X เสมอ
    // ทุกคอลัมน์ แล้วส่งมันไปทางขอบ ซึ่ง m_rdy_wire ถูก tie ไว้ที่ 0 — flit จะค้าง
    // ตรงนั้นถาวร บล็อกหัวคิวตามมาทั้งสาย ไม่มีธง ไม่มี timeout
    // host ตัวเดียวที่พิมพ์ปลายทางผิดจึงแขวนเมชได้ทั้งใบ
    //
    // ทางเลือกที่ไม่เอา: ดึง s_ready ลง (เท่ากับย้ายการค้างไปที่ผู้ส่งแทน) และ
    // การหนีบค่าให้เข้าช่วง (flit จะไปโผล่โหนดที่ไม่ได้ตั้งใจแบบเงียบๆ)
    // ที่เลือกคือ ทิ้ง flit ทิ้งไปเลยแต่ยังรับเข้ามาตามปกติ แล้วยกธง sticky
    // ผู้ส่งไม่ค้าง เมชไม่ตัน แพกเกจที่ผิดหายไปทั้งใบ (tdest คงที่ต่อแพกเกจ
    // เป็นสัญญาที่ router พึ่งอยู่แล้ว) และมีธงบอกว่าทำไมของถึงหาย
    // เส้นทางรายงานเดินตาม ECC ทุกประการ: sticky ต่อโหนด -> รวมที่ gals_noc_top
    // -> ตัวนับ mark_debug ให้ ILA อ่าน -> LED
    // =================================================================
    localparam logic [1:0] MAX_X = 2'd1;   // กระดาน 2x2 : x และ y ใช้ได้แค่ 0..1
    localparam logic [1:0] MAX_Y = 2'd1;

    logic [3:0] dest_ok;
    always_comb begin
        for (int i = 0; i < 4; i++) begin
            dest_ok[i] = (s_tdest[i][3:2] <= MAX_X) && (s_tdest[i][1:0] <= MAX_Y);
        end
    end

    // -----------------------------------------------------------------
    // 0b. ตรวจ tid ก่อนปล่อยเข้าเมช
    //
    // tid เป็น one-hot: 01 = VC0, 10 = VC1 ทุกจุดที่ใช้มัน and กับ valid ไว้แล้ว
    // (fifo_we = s_valid && s_tid[v] ใน vc_input_buffer,
    //  w_en = s_noc_valid && s_noc_tid[v] ใน gals_node_wrapper)
    // ผลคือ tid = 00 ไม่ตรงกับเลนไหนเลย flit ถูกทิ้งเงียบๆ ไม่มีใครรู้
    // ส่วน tid = 11 ยิ่งแย่กว่า: flit เดียวถูกเขียนลงทั้งสอง VC = ถูกโคลน
    //
    // ไม่มีอะไรใน RTL บังคับข้อนี้เลย มันอยู่แค่ใน assume ของ formal
    // และนี่คือรูปแบบความผิดพลาดเดิมที่กัดมาแล้วสามรอบ:
    //   พอร์ต ECC ปล่อยลอย -> ปลายทางนอกกระดาน -> tid = 00 ใน noc_host.py
    // ทุกครั้งอาการเหมือนกันหมดคือของหายเงียบๆ แล้วไล่หาต้นตอไม่เจอ
    // คราวนี้เลยปิดทั้งคลาส ด้วยท่าเดียวกับ dest_err: ทิ้ง flit แล้วยกธง
    // -----------------------------------------------------------------
    logic [3:0] tid_ok;
    always_comb begin
        for (int i = 0; i < 4; i++) begin
            // one-hot เป๊ะ: มีบิตเดียว ไม่ใช่ศูนย์ ไม่ใช่สองบิต
            tid_ok[i] = (s_tid[i] != '0) && ((s_tid[i] & (s_tid[i] - 1'b1)) == '0);
        end
    end

    // ยกธงตั้งแต่ตอน *เสนอ* flit ที่ผิด ไม่ต้องรอให้ถูกรับ — ความผิดอยู่ที่การยิง
    // ปลายทางนอกกระดาน ไม่ใช่ที่จังหวะ handshake
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            dest_err <= '0;
            tid_err  <= '0;
        end else begin
            for (int i = 0; i < 4; i++) begin
                if (s_valid[i] && !dest_ok[i]) dest_err[i] <= 1'b1;
                if (s_valid[i] && !tid_ok[i])  tid_err[i]  <= 1'b1;
            end
        end
    end

    // =================================================================
    // 2. เดินสายไฟ (WIRING LOGIC) ⚡
    // =================================================================
    generate
        for (genvar i = 0; i < 4; i++) begin : LOCAL_PORTS
            // 2.1 เชื่อมพอร์ต LOCAL (0) ลงไปหา Host (ผ่าน Wrapper)
            // flit ที่จ่าหน้านอกกระดาน / tid ไม่ one-hot ไม่ถูกปล่อยเข้าเมชเลย
            // (เหตุผลอยู่หัวข้อ 0 และ 0b)
            wire flit_ok = dest_ok[i] && tid_ok[i];
            wire reject  = s_valid[i] && !flit_ok;

            // ---------------------------------------------------------
            // 2.2 ปิดแพกเกจที่ค้างเปิดอยู่เมื่อมี flit ถูกปฏิเสธ (bug #7)
            //
            // ตัวกรองข้างบนทิ้ง flit ทั้งใบ ถ้าใบนั้นมี tlast ติดมาด้วย tlast ก็หาย
            // ไปพร้อมกัน แต่ packet_arbiter ข้างล่างรู้ขอบแพกเกจจาก tlast เท่านั้น
            // มันไม่มีทางรู้ว่าเคยมี flit ใบหนึ่งถูกกินไป แพกเกจบน VC นั้นจึงค้าง
            // เปิด แล้ว flit ถัดไปที่ผ่านตัวกรองมาปกติ (หัวแพกเกจใหม่ จ่าหน้าคนละ
            // โหนด) ถูกนับเป็นตัวแพกเกจเดิม วิ่งตาม grant เดิม ไปโผล่ผิดโหนด
            // ยืนยันจาก counterexample ของ assert_eject_dest (HANDOFF 3c)
            //
            // ทางแก้: จำไว้ต่อ VC ว่ามีแพกเกจเปิดค้างอยู่ไหม (หัวเข้าแล้ว tlast ยัง)
            // พอมี flit ถูกปฏิเสธ ให้ยิง tlast สังเคราะห์ปิดทุก VC ที่ยังเปิด
            // ใช้ tdest ของหัวแพกเกจนั้นๆ (ผ่าน dest_ok มาแล้ว) data เป็น 0
            // แพกเกจถูกส่งถึงปลายทางที่ถูกต้องแบบขาดท้าย และธง dest_err/tid_err
            // ยกอยู่แล้ว ดีกว่าปล่อยให้แพกเกจถัดไปถูกส่งผิดโหนดเงียบๆ
            //
            // ปิดทุก VC ที่เปิดอยู่ ไม่พยายามเดาว่า flit ที่ผิดตั้งใจจะไป VC ไหน
            // (tid=00 ชี้ไม่ได้, tid=11 ชี้สองทาง) — host ที่ยิง tid/tdest เพี้ยน
            // ไว้ใจเรื่อง framing ไม่ได้อยู่แล้ว การตัดแพกเกจข้างเคียงสั้นลง
            // เป็นราคาที่รับได้ เทียบกับการส่งของผิดโหนด
            //
            // การยิงปิดใช้พอร์ต LOCAL ของ router ซึ่งรับได้ทีละ flit จึงต้องคิว
            // (close_pend) แล้วปิดทีละ VC พร้อมดึง s_ready ลงกัน host ยิงซ้อน
            // ระหว่างนั้น host ยังยก valid ค้างได้ตามปกติ แค่ไม่ถูกรับจนกว่าจะปิดครบ
            // ---------------------------------------------------------
            logic [NUM_VCS-1:0]      pkt_open;
            logic [NUM_VCS-1:0][3:0] pkt_dest;
            logic [NUM_VCS-1:0]      close_pend;
            logic [NUM_VCS-1:0]      close_sel;   // one-hot: VC ที่กำลังยิงปิด
            logic                    closing;

            always_comb begin
                close_sel = '0;
                for (int v = NUM_VCS-1; v >= 0; v--) begin
                    if (close_pend[v]) close_sel = NUM_VCS'(1) << v;
                end
                closing = |close_pend;
            end

            // flit จริงที่ถูกรับเข้า router (ต่อ VC) — ใช้ตาม pkt_open
            wire [NUM_VCS-1:0] host_acc = {NUM_VCS{s_valid[i] && flit_ok && !closing}}
                                          & s_tid[i] & r_rdy[i][LOCAL];
            // การยิงปิดถูกรับ
            wire [NUM_VCS-1:0] close_acc = close_sel & r_rdy[i][LOCAL];

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    pkt_open   <= '0;
                    close_pend <= '0;
                    pkt_dest   <= '0;
                end else begin
                    for (int v = 0; v < NUM_VCS; v++) begin
                        if (close_acc[v]) begin
                            pkt_open[v]   <= 1'b0;
                            close_pend[v] <= 1'b0;
                        end else if (host_acc[v]) begin
                            if (!pkt_open[v]) pkt_dest[v] <= s_tdest[i];
                            pkt_open[v] <= !s_tlast[i];
                        end else if (reject && pkt_open[v]) begin
                            close_pend[v] <= 1'b1;
                        end
                    end
                end
            end

            // ---- เลือกว่าเสนออะไรให้ router: flit สังเคราะห์ปิด หรือ flit ของ host
            always_comb begin
                if (closing) begin
                    r_valid[i][LOCAL] = 1'b1;
                    r_last[i][LOCAL]  = 1'b1;
                    r_tid[i][LOCAL]   = close_sel;
                    r_dat[i][LOCAL]   = '0;
                    r_dst[i][LOCAL]   = '0;
                    for (int v = 0; v < NUM_VCS; v++)
                        if (close_sel[v]) r_dst[i][LOCAL] = pkt_dest[v];
                    s_ready[i]        = '0;
                end else begin
                    // flit ที่ถูกปฏิเสธต้องไม่เหลืออะไรไว้บนสายเลย ไม่ใช่แค่ดึง valid ลง
                    r_valid[i][LOCAL] = s_valid[i] && flit_ok;
                    r_last[i][LOCAL]  = s_tlast[i] && flit_ok;
                    r_dst[i][LOCAL]   = flit_ok ? s_tdest[i] : '0;
                    r_dat[i][LOCAL]   = flit_ok ? s_tdata[i] : '0;
                    r_tid[i][LOCAL]   = flit_ok ? s_tid[i]   : '0;
                    s_ready[i]        = r_rdy[i][LOCAL];
                end
            end

            assign ing_closing[i]    = closing;
            assign ing_pkt_open[i]   = pkt_open;
            assign ing_close_pend[i] = close_pend;
            assign ing_close_acc[i]  = close_acc;

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
    // 3. ปิดขอบกระดาน (Tie-off) ป้องกัน Undefined State และ Floating Wires
    // =================================================================
    
    // Node 00 (X=0, Y=0): ทิศ SOUTH, WEST ติดขอบ
    assign r_valid[0][SOUTH] = 1'b0; assign m_rdy_wire[0][SOUTH] = '0;
    assign r_last[0][SOUTH]  = 1'b0; assign r_dst[0][SOUTH] = '0; assign r_dat[0][SOUTH] = '0; assign r_tid[0][SOUTH] = '0;
    assign r_valid[0][WEST]  = 1'b0; assign m_rdy_wire[0][WEST]  = '0;
    assign r_last[0][WEST]   = 1'b0; assign r_dst[0][WEST]  = '0; assign r_dat[0][WEST]  = '0; assign r_tid[0][WEST]  = '0;

    // Node 10 (X=1, Y=0): ทิศ SOUTH, EAST ติดขอบ
    assign r_valid[1][SOUTH] = 1'b0; assign m_rdy_wire[1][SOUTH] = '0;
    assign r_last[1][SOUTH]  = 1'b0; assign r_dst[1][SOUTH] = '0; assign r_dat[1][SOUTH] = '0; assign r_tid[1][SOUTH] = '0;
    assign r_valid[1][EAST]  = 1'b0; assign m_rdy_wire[1][EAST]  = '0;
    assign r_last[1][EAST]   = 1'b0; assign r_dst[1][EAST]  = '0; assign r_dat[1][EAST]  = '0; assign r_tid[1][EAST]  = '0;

    // Node 01 (X=0, Y=1): ทิศ NORTH, WEST ติดขอบ
    assign r_valid[2][NORTH] = 1'b0; assign m_rdy_wire[2][NORTH] = '0;
    assign r_last[2][NORTH]  = 1'b0; assign r_dst[2][NORTH] = '0; assign r_dat[2][NORTH] = '0; assign r_tid[2][NORTH] = '0;
    assign r_valid[2][WEST]  = 1'b0; assign m_rdy_wire[2][WEST]  = '0;
    assign r_last[2][WEST]   = 1'b0; assign r_dst[2][WEST]  = '0; assign r_dat[2][WEST]  = '0; assign r_tid[2][WEST]  = '0;

    // Node 11 (X=1, Y=1): ทิศ NORTH, EAST ติดขอบ
    assign r_valid[3][NORTH] = 1'b0; assign m_rdy_wire[3][NORTH] = '0;
    assign r_last[3][NORTH]  = 1'b0; assign r_dst[3][NORTH] = '0; assign r_dat[3][NORTH] = '0; assign r_tid[3][NORTH] = '0;
    assign r_valid[3][EAST]  = 1'b0; assign m_rdy_wire[3][EAST]  = '0;
    assign r_last[3][EAST]   = 1'b0; assign r_dst[3][EAST]  = '0; assign r_dat[3][EAST]  = '0; assign r_tid[3][EAST]  = '0;


    // =================================================================
    // FORMAL
    //
    // ชั้นนี้แทบไม่มีตรรกะเลย มีแต่ assign เดินสายด้วยมือ 36 บรรทัด กับ
    // tie-off ปิดขอบ — ซึ่งเป็นทรงที่บั๊กแบบ "ต่อสลับดัชนี" ชอบซ่อนอยู่พอดี
    // และเป็นบั๊กที่ testbench ระดับบนจับได้ยาก เพราะแพกเกจยังวิ่งได้ แค่ไป
    // โผล่ผิดโหนด
    //
    // property หลักสองข้อ:
    //   assert_eject_dest    - flit ที่เด้งออก LOCAL ของโหนด i ต้องจ่าหน้ามาที่
    //                          โหนด i จริง นี่คือความถูกต้องปลายทางระดับเมช
    //                          ถ้าเดินสายสลับ idx ข้อนี้จะพังทันที
    //   assert_edge_*        - ไม่มี router ตัวไหนคาย valid ออกขอบกระดาน
    //                          ขอบถูก tie m_rdy_wire = 0 ไว้ ถ้ามี flit วิ่งไปทางนั้น
    //                          มันจะค้างตรงนั้นตลอดกาลและบล็อกหัวคิวตามมา
    //
    // ข้อสมมติที่ต้องมี และเป็น "สัญญา" ที่ RTL ไม่ได้บังคับไว้:
    //   tdest ต้องอยู่ในกระดาน — x และ y ต้องเป็น 0 หรือ 1 เท่านั้น
    //   s_tdest กว้าง 4 บิต (x=[3:2], y=[1:0]) รับค่าได้ถึง 3 แต่เมชมีแค่ 2x2
    //   ยิง tdest ที่ x=2/3 หรือ y=2/3 เข้าไป XY routing จะพาออกขอบกระดาน
    //   แล้ว flit จะค้างถาวร ไม่มีธง ไม่มี timeout — เป็นการแขวนเมชทั้งใบ
    //   จาก host ตัวเดียว ตัว agent ในโปรเจกต์นี้ยิงแต่ค่าในช่วง จึงไม่เจอ
    //
    // routers ถูกอ่านด้วย -D FORMAL_NO_ROUTER เพื่อ *ปิด* บล็อก FORMAL ของมันเอง
    // ไม่ใช่เพื่อความเร็ว แต่เพราะบล็อกนั้นมี assume เรื่องทราฟฟิกที่ถูกรูปแบบ
    // ซึ่งในบริบทเมชจะไปตกอยู่บนสายภายในที่มีตัวขับอยู่แล้ว assume บนสายที่ถูกขับ
    // อาจขัดแย้งกันเองจนทุก assertion ผ่านแบบ vacuous คือดูเขียวแต่ไม่ได้พิสูจน์อะไร
    // ตัว router พิสูจน์แยกใน router_5port_mesh_vc.sby ที่ขา s_* เป็น input จริง
    // =================================================================
    `ifdef FORMAL
        reg f_past_valid = 1'b0;
        always @(posedge clk) f_past_valid <= 1'b1;

        // FIFO และ state ของ arbiter ไม่มีค่า init บังคับให้ผ่านรีเซ็ตก่อนหนึ่งไซเคิล
        reg f_init = 1'b1;
        always @(posedge clk) f_init <= 1'b0;
        always @(*) if (f_init) assume(!rst_n);

        // yosys+slang ยังไม่รองรับ $onehot/$onehot0 จึงเขียนเองด้วยเลขฐานสอง
        function automatic bit f_onehot0(input logic [15:0] v);
            f_onehot0 = ((v & (v - 16'd1)) == 16'd0);
        endfunction
        function automatic bit f_onehot(input logic [15:0] v);
            f_onehot = (v != 16'd0) && ((v & (v - 16'd1)) == 16'd0);
        endfunction

        // ---------------------------------------------------------
        // ข้อสมมติที่ขา host ทั้ง 4 โหนด (เป็น input จริงของ top ตัวนี้)
        // ---------------------------------------------------------
        generate
            for (genvar i = 0; i < 4; i++) begin : f_host
                always @(*) begin
                    if (rst_n && s_valid[i]) begin
                        // ไม่ assume ว่า s_tid เป็น one-hot แล้ว — เหมือนกรณี tdest
                        // ที่ถอด assume ทิ้งได้หลังใส่ตัวกรอง รอบก่อนถอดไม่ได้เพราะ
                        // assert_eject_dest พังที่ step 4 (node 0 เด้ง flit tdest=0100)
                        // ซึ่งคือ bug #7: flit ที่ถูกปฏิเสธพา tlast หายไปด้วย แพกเกจ
                        // บน VC นั้นค้างเปิด แล้วกลืน flit ถัดไปไปส่งผิดโหนด
                        // (HANDOFF 3c) หัวข้อ 2.2 ปิดแพกเกจค้างให้แล้ว solver จึงยิง
                        // tid ได้ทุกค่า 00..11 และ assert_eject_dest ต้องยืนได้เอง
                        // ข้อ backpressure ยกเว้นตอนกำลังปิดแพกเกจ: s_ready ถูกดึงลง
                        // ทั้งคู่โดยตั้งใจ host ที่ valid ค้างอยู่ตอนนั้นคือเคสที่ต้องตรวจ
                        if (!ing_closing[i]) assume((s_tid[i] & ~s_ready[i]) == '0);
                        // ไม่มี assume เรื่องช่วงของ s_tdest แล้วโดยตั้งใจ:
                        // เดิมต้อง assume ว่าปลายทางอยู่ในกระดาน ไม่งั้น assert_edge_*
                        // พังจริง ตอนนี้หัวข้อ 0 กรอง flit นอกกระดานออกก่อนเข้าเมช
                        // จึงปล่อยให้ solver ยิง tdest ได้ทุกค่า 0..15 แล้วพิสูจน์ว่า
                        // ไม่มีอะไรหลุดออกขอบ = ข้อสมมติเดิมกลายเป็นข้อพิสูจน์
                    end
                end

                // ทุก flit ในแพกเกจเดียวกันต้องจ่าหน้าที่เดียวกัน
                // (เหตุผลเต็มอยู่ใน router_5port_mesh_vc.sv บล็อก f_wf)
                for (genvar vc = 0; vc < NUM_VCS; vc++) begin : f_host_vc
                    logic       f_in_pkt;
                    logic [3:0] f_in_dest;
                    wire f_acc = s_valid[i] && s_tid[i][vc] && s_ready[i][vc];

                    always_ff @(posedge clk or negedge rst_n) begin
                        if (!rst_n) begin
                            f_in_pkt <= 1'b0;
                        end else if (f_acc) begin
                            if (s_tlast[i]) begin
                                f_in_pkt <= 1'b0;
                            end else begin
                                f_in_pkt  <= 1'b1;
                                f_in_dest <= s_tdest[i];
                            end
                        end
                    end

                    always @(*) begin
                        if (rst_n && f_in_pkt && s_valid[i] && s_tid[i][vc])
                            assume(s_tdest[i] == f_in_dest);
                    end
                end
            end
        endgenerate

        // ---------------------------------------------------------
        // property ระดับเมช
        // ---------------------------------------------------------
        generate
            for (genvar i = 0; i < 4; i++) begin : f_node
                localparam logic [1:0] NX = i % 2;   // idx = y*2 + x
                localparam logic [1:0] NY = i / 2;

                always @(*) begin
                    if (rst_n && f_past_valid) begin
                        // ---- ไม่มีใครคาย valid ออกขอบกระดาน
                        if (NX == 2'd0) begin
                            assert_edge_west:  assert(!m_valid_wire[i][WEST]);
                        end else begin
                            assert_edge_east:  assert(!m_valid_wire[i][EAST]);
                        end
                        if (NY == 2'd0) begin
                            assert_edge_south: assert(!m_valid_wire[i][SOUTH]);
                        end else begin
                            assert_edge_north: assert(!m_valid_wire[i][NORTH]);
                        end

                        // ---- ของที่เด้งออก LOCAL ต้องเป็นของโหนดนี้จริง
                        if (m_valid[i]) begin
                            assert_eject_dest: assert(m_tdest[i] == {NX, NY});
                            assert_eject_tid:  assert(f_onehot(m_tid[i]));
                        end

                        // ---- flit ที่จ่าหน้านอกกระดานต้องไม่ถูกปล่อยเข้าเมช
                        // ถ้าหลุดเข้าไปได้ มันจะวิ่งไปตันที่ขอบและบล็อกหัวคิวถาวร
                        // สิ่งเดียวที่เข้าได้ตอน flit ผิดคือ tlast สังเคราะห์ (2.2)
                        if (s_valid[i] && !dest_ok[i]) begin
                            assert_bad_dest_blocked:
                                assert(!r_valid[i][LOCAL] || ing_closing[i]);
                        end
                        // ทุกอย่างที่เข้า router ผ่าน LOCAL ต้องจ่าหน้าในกระดานเสมอ
                        // รวม flit สังเคราะห์ด้วย (ใช้ tdest ของหัวแพกเกจที่ผ่านกรองแล้ว)
                        if (r_valid[i][LOCAL]) begin
                            assert_local_in_range:
                                assert((r_dst[i][LOCAL][3:2] <= MAX_X) &&
                                       (r_dst[i][LOCAL][1:0] <= MAX_Y));
                            assert_local_tid_onehot: assert(f_onehot(r_tid[i][LOCAL]));
                        end
                        // ตัวกรองห้ามแตะของที่ถูกต้อง ไม่ใช่แค่กันของผิด
                        if (s_valid[i] && dest_ok[i] && tid_ok[i] && !ing_closing[i]) begin
                            assert_good_flit_passes: assert(r_valid[i][LOCAL]);
                        end
                        // ตัวปิดแพกเกจค้าง: ปิดได้เฉพาะ VC ที่เปิดอยู่จริง
                        // ไม่งั้นจะยิง tlast ลอยๆ ใส่ VC ว่าง = แพกเกจผีหนึ่ง flit
                        assert_close_pend_only_open:
                            assert((ing_close_pend[i] & ~ing_pkt_open[i]) == '0);
                        // และระหว่างปิด host ต้องถูกกันไว้จริง
                        if (ing_closing[i]) begin
                            assert_host_held_while_closing: assert(s_ready[i] == '0);
                        end

                        // ป้าย VC ห้ามติดสองเลนพร้อมกัน ไม่ว่าจะมี valid หรือไม่
                        // ถ้า multi-hot ปลายทางจะเขียน flit เดียวลงสอง VC = โคลน
                        // (ข้อนี้ตรวจซ้ำจากฝั่งเมช โดยที่บล็อก FORMAL ของ router ปิดอยู่
                        //  จึงเป็นการยืนยันอิสระ ไม่ได้อาศัย assert_xbar_onehot)
                        assert_eject_tid_onehot0: assert(f_onehot0(m_tid[i]));
                    end
                end
            end
        endgenerate

        // -------------------------------------------------------------
        // COVER: เมชต้องส่งของถึงจริงทั้ง 4 โหนด และลิงก์ต้องมีของวิ่งจริง
        // ข้อจำกัด: cover พวกนี้บอกได้แค่ว่า "มีของถึงโหนดนั้น" ไม่ได้แยกว่า
        // มาจากเพื่อนบ้านหนึ่งฮ็อปหรือมาจากมุมตรงข้ามสองฮ็อป
        // -------------------------------------------------------------
        reg f_closed_seen = 1'b0;
        always @(posedge clk) if (rst_n && (|ing_close_acc[0])) f_closed_seen <= 1'b1;

        always @(posedge clk) begin
            if (f_past_valid && $past(rst_n) && rst_n) begin
                cover_deliver_n0: cover(m_valid[0] && (|m_ready[0]));
                cover_deliver_n1: cover(m_valid[1] && (|m_ready[1]));
                cover_deliver_n2: cover(m_valid[2] && (|m_ready[2]));
                cover_deliver_n3: cover(m_valid[3] && (|m_ready[3]));

                // ลิงก์แกนนอนและแกนตั้งมีของวิ่งจริง (ไม่ใช่เมชที่ตายอยู่)
                cover_link_x: cover(m_valid_wire[0][EAST]);
                cover_link_y: cover(m_valid_wire[0][NORTH]);

                // สอง VC วิ่งพร้อมกันคนละโหนด
                cover_both_vcs: cover(m_valid[0] && m_tid[0][0] &&
                                      m_valid[3] && m_tid[3][1]);

                // ตัวกรองปลายทางถูกกระตุ้นได้จริง ไม่ใช่โค้ดที่ไม่มีทางทำงาน
                // (ถ้า cover นี้ไม่ถึง แปลว่า assert_bad_dest_blocked ผ่านแบบ vacuous)
                cover_dest_err_raised: cover(|dest_err);
                cover_tid_err_raised:  cover(|tid_err);

                // ตัวปิดแพกเกจค้าง (2.2) ไปถึงได้จริง: มีแพกเกจเปิดอยู่แล้ว flit ผิดโผล่มา
                // แล้ว tlast สังเคราะห์ถูก router รับ — ถ้าไม่ถึง assert ข้างบนคือ vacuous
                cover_force_close: cover(|ing_close_acc[0]);
                // ปิดแล้วเมชยังส่ง tlast ออกโหนด 0 ได้ (ท้ายสังเคราะห์เดินถึงปลายทาง
                // จริง ไม่ได้ปิดแล้วค้าง)
                cover_deliver_after_close: cover(f_closed_seen && m_valid[0] && m_tlast[0]);
                cover_mesh_alive_after_bad_dest:
                    cover((|dest_err) && (m_valid[0] || m_valid[1] ||
                                          m_valid[2] || m_valid[3]));
            end
        end
    `endif

endmodule

