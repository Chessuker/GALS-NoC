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
    input  logic [3:0][NUM_VCS-1:0] m_ready
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
    // 2. เดินสายไฟ (WIRING LOGIC) ⚡
    // =================================================================
    generate
        for (genvar i = 0; i < 4; i++) begin : LOCAL_PORTS
            // 2.1 เชื่อมพอร์ต LOCAL (0) ลงไปหา Host (ผ่าน Wrapper)
            assign r_valid[i][LOCAL] = s_valid[i];
            assign r_last[i][LOCAL]  = s_tlast[i];
            assign r_dst[i][LOCAL]   = s_tdest[i];
            assign r_dat[i][LOCAL]   = s_tdata[i];
            assign r_tid[i][LOCAL]   = s_tid[i];
            assign s_ready[i]        = r_rdy[i][LOCAL];

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
                        assume(f_onehot(s_tid[i]));
                        assume((s_tid[i] & ~s_ready[i]) == '0);
                        // ปลายทางต้องอยู่ในกระดาน 2x2 (เหตุผลเต็มอยู่หัวบล็อก)
                        assume(s_tdest[i][3:2] <= 2'd1);
                        assume(s_tdest[i][1:0] <= 2'd1);
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
            end
        end
    `endif

endmodule

