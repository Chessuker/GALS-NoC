`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/03/2026 10:40:32 PM
// Design Name: 
// Module Name: router_5port_mesh_vc
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


module router_5port_mesh_vc #(
    parameter [1:0] MY_X = 2'd0,
    parameter [1:0] MY_Y = 2'd0,
    parameter DATA_W = 8,
    parameter CORD_W = 2,
    parameter NUM_VCS = 2,
    parameter DEPTH = 16
)(
    input  logic clk,
    input  logic rst_n,

    // 5 Input Ports (0:Local, 1:North, 2:South, 3:East, 4:West)
    input  logic [4:0]              s_valid,
    input  logic [4:0]              s_tlast,
    input  logic [4:0][3:0]         s_tdest,
    input  logic [4:0][DATA_W-1:0]  s_tdata,
    input  logic [4:0][NUM_VCS-1:0] s_tid,
    output logic [4:0][NUM_VCS-1:0] s_ready,

    // 5 Output Ports
    output logic [4:0]              m_valid,
    output logic [4:0]              m_tlast,
    output logic [4:0][3:0]         m_tdest,
    output logic [4:0][DATA_W-1:0]  m_tdata,
    output logic [4:0][NUM_VCS-1:0] m_tid,
    input  logic [4:0][NUM_VCS-1:0] m_ready
);

    localparam LOCAL = 0, NORTH = 1, SOUTH = 2, EAST = 3, WEST = 4;

    // =========================================================
    // 1. VC Input Buffers (กล่องคัดแยกจดหมาย 5 ทิศทาง)
    // =========================================================
    logic              buf_valid [5][NUM_VCS];
    logic              buf_tlast [5][NUM_VCS];
    logic [3:0]        buf_tdest [5][NUM_VCS];
    logic [DATA_W-1:0] buf_tdata [5][NUM_VCS];
    logic              buf_ready [5][NUM_VCS];

    generate
        for (genvar p = 0; p < 5; p++) begin : GEN_IN_BUF
            vc_input_buffer #(
                .DATA_W(DATA_W), .CORD_W(CORD_W), .NUM_VCS(NUM_VCS), .DEPTH(DEPTH)
            ) in_buf (
                .clk(clk), .rst_n(rst_n),
                .s_valid(s_valid[p]), .s_tlast(s_tlast[p]), .s_tdest(s_tdest[p]), .s_tdata(s_tdata[p]), .s_tid(s_tid[p]), .s_ready(s_ready[p]),
                .m_valid(buf_valid[p]), .m_tlast(buf_tlast[p]), .m_tdest(buf_tdest[p]), .m_tdata(buf_tdata[p]), .m_ready(buf_ready[p])
            );
        end
    endgenerate

    // =========================================================
    // 2. X-Y Routing Decoder (ดูจ่าหน้าซอง ว่าจะส่งออกพอร์ตไหน)
    // =========================================================
    logic [4:0] route_req [5][NUM_VCS]; // [in_port][vc][out_port]

    always_comb begin
        for (int in_p = 0; in_p < 5; in_p++) begin
            for (int vc = 0; vc < NUM_VCS; vc++) begin
                route_req[in_p][vc] = '0;
                if (buf_valid[in_p][vc]) begin
                    automatic logic [1:0] dx = buf_tdest[in_p][vc][3:2];
                    automatic logic [1:0] dy = buf_tdest[in_p][vc][1:0];

                    if      (dx > MY_X) route_req[in_p][vc][EAST]  = 1'b1;
                    else if (dx < MY_X) route_req[in_p][vc][WEST]  = 1'b1;
                    else if (dy > MY_Y) route_req[in_p][vc][NORTH] = 1'b1;
                    else if (dy < MY_Y) route_req[in_p][vc][SOUTH] = 1'b1;
                    else                route_req[in_p][vc][LOCAL] = 1'b1;
                end
            end
        end
    end

    // =================================================================
    // 2.5 จัดสายสัญญาณ (Transpose) จาก Input-centric เป็น Output-centric
    // =================================================================
    logic [4:0] req_out_vc0 [5];
    logic [4:0] req_out_vc1 [5];
    logic [4:0] last_out_vc0 [5];
    logic [4:0] last_out_vc1 [5];
    
    logic [4:0] grant_vc0 [5];
    logic [4:0] grant_vc1 [5];
    logic       ready_from_arb_vc0 [5];
    logic       ready_from_arb_vc1 [5];

    always_comb begin
        for (int out_p = 0; out_p < 5; out_p++) begin
            for (int in_p = 0; in_p < 5; in_p++) begin
                req_out_vc0[out_p][in_p]  = route_req[in_p][0][out_p];
                req_out_vc1[out_p][in_p]  = route_req[in_p][1][out_p];
                last_out_vc0[out_p][in_p] = buf_tlast[in_p][0];
                last_out_vc1[out_p][in_p] = buf_tlast[in_p][1];
            end
        end
    end

    // =================================================================
    // 3. Port Arbiters (เรียกใช้ตัวตัดสินใจการแย่งเลน 5 พอร์ต)
    // =================================================================
    generate
        for (genvar out_p = 0; out_p < 5; out_p++) begin : GEN_ARB
            vc_port_arbiter #(
                .PORTS(5)
            ) arb_inst (
                .clk(clk), 
                .rst_n(rst_n),
                // สัญญาณขอใช้เส้นทางจาก Input — ชื่อต้องตรงกับ arbiter
                .valid_vc1(req_out_vc1[out_p]), 
                .tlast_vc1(last_out_vc1[out_p]),
                .grant_vc1(grant_vc1[out_p]),

                .valid_vc0(req_out_vc0[out_p]), 
                .tlast_vc0(last_out_vc0[out_p]),
                .grant_vc0(grant_vc0[out_p]),

                // ดึง m_ready จาก Router ปลายทางมาเช็คก่อนให้ Grant
                .ready_out_vc1(m_ready[out_p][1]), 
                .ready_out_vc0(m_ready[out_p][0]), 

                // สัญญาณ Ready ตีกลับไปหา Input Buffer
                .ready_vc1(ready_from_arb_vc1[out_p]),
                .ready_vc0(ready_from_arb_vc0[out_p])
            );
        end
    endgenerate

    // =================================================================
    // 4. Crossbar Switch (สับรางรถไฟ) - ONE-HOT AND-OR MUX (Optimized)
    // =================================================================
    always_comb begin
        for (int out_p = 0; out_p < 5; out_p++) begin
            // 1. เคลียร์ค่าเริ่มต้นให้เป็น 0 ให้หมด (ฐานของ OR-Tree)
            m_valid[out_p] = 1'b0;
            m_tlast[out_p] = 1'b0;
            m_tdest[out_p] = '0;
            m_tdata[out_p] = '0;
            m_tid[out_p]   = '0;

            // 2. จับ Data มา AND กับ Grant แล้ว OR รวมกันแบบขนานทั้งหมด
            for (int in_p = 0; in_p < 5; in_p++) begin
                // ------ สำหรับ VC1 ------
                m_valid[out_p] |= (buf_valid[in_p][1] & grant_vc1[out_p][in_p]);
                m_tlast[out_p] |= (buf_tlast[in_p][1] & grant_vc1[out_p][in_p]);
                m_tdest[out_p] |= (buf_tdest[in_p][1] & {4{grant_vc1[out_p][in_p]}});
                m_tdata[out_p] |= (buf_tdata[in_p][1] & {DATA_W{grant_vc1[out_p][in_p]}});

                // ------ สำหรับ VC0 ------
                m_valid[out_p] |= (buf_valid[in_p][0] & grant_vc0[out_p][in_p]);
                m_tlast[out_p] |= (buf_tlast[in_p][0] & grant_vc0[out_p][in_p]);
                m_tdest[out_p] |= (buf_tdest[in_p][0] & {4{grant_vc0[out_p][in_p]}});
                m_tdata[out_p] |= (buf_tdata[in_p][0] & {DATA_W{grant_vc0[out_p][in_p]}});
            end

            // 3. จัดการ m_tid แยกต่างหาก (เพื่อความเร็ว)
            m_tid[out_p] = (2'b10 & {2{|grant_vc1[out_p]}}) | 
                           (2'b01 & {2{|grant_vc0[out_p]}});
        end
    end

    // ดึงสัญญาณ Ready คืนกลับไปบอก Input Buffers (OR logic)
    always_comb begin
        for (int in_p = 0; in_p < 5; in_p++) begin
            buf_ready[in_p][0] = 1'b0;
            buf_ready[in_p][1] = 1'b0;
            for (int out_p = 0; out_p < 5; out_p++) begin
                if (grant_vc0[out_p][in_p]) buf_ready[in_p][0] |= ready_from_arb_vc0[out_p];
                if (grant_vc1[out_p][in_p]) buf_ready[in_p][1] |= ready_from_arb_vc1[out_p];
            end
        end
    end


    // =================================================================
    // FORMAL
    //
    // เราพิสูจน์ arbiter ไปแล้วทั้งสองชั้น แต่ router ที่ห่อมันอยู่ยังไม่เคย
    // ถูกแตะเลย ทั้งที่ชิ้นส่วนที่เหลืออีกสองชิ้นเป็นจุดที่บั๊กเส้นทางจะซ่อนอยู่:
    //   - ตัวถอด XY : ส่งผิดทาง หรือเด้งแพกเกจของคนอื่นออก LOCAL
    //   - crossbar  : เป็น AND-OR mux ซึ่งถูกต้องได้ก็ต่อเมื่อ grant เป็น one-hot
    //                 ถ้ามีสอง input ได้ไฟเขียวพร้อมกัน ผลลัพธ์คือ OR ของข้อมูล
    //                 สองชุด = flit ประกอบร่างใหม่แบบเงียบๆ ไม่มีธงอะไรขึ้นเลย
    //
    // property ที่แรงที่สุดในบล็อกนี้คือ assert_no_grant_fanout_*:
    // arbiter ล็อกช่องข้ามไซเคิลได้ (packet lock) ถ้าหัวคิวของ input เดิม
    // เปลี่ยนเส้นทางกลางแพกเกจ arbiter ตัวเก่าจะยังถือ grant อยู่ ขณะที่ arbiter
    // ของพอร์ตใหม่ก็ให้ grant ด้วย พอร์ตออกสองพอร์ตจึงอ่าน input buffer เดียวกัน
    // แต่ buf_ready ถูก OR รวมเป็นเส้นเดียว = FIFO ถูกอ่านครั้งเดียว แต่ flit
    // ถูกคายออกสองทาง นั่นคือ flit ถูกโคลน
    //
    // property เป็น structural บนสาย grant/route ไม่ขึ้นกับเนื้อใน FIFO
    // จึงพิสูจน์แบบ unbounded (prove) ได้ ต่างจาก vc_input_buffer ที่ต้องเทียบ
    // เนื้อคิวจึงได้แค่ bounded
    //
    // ทำไมใช้ generate/genvar ไม่ใช่ for ธรรมดา: frontend slang ตั้งชื่อเซลล์
    // assert ตาม label ตรงๆ ป้ายซ้ำใน loop ธรรมดาจะชนกันแล้ว yosys assert-fail
    // ที่ rtlil.cc (count_id) — generate ทำให้ label ได้ prefix ลำดับชั้นที่ไม่ซ้ำ
    // =================================================================
    `ifdef FORMAL
    `ifndef FORMAL_NO_ROUTER
        reg f_past_valid = 1'b0;
        always @(posedge clk) f_past_valid <= 1'b1;

        // FIFO ใน vc_input_buffer และ state ของ arbiter ไม่มีค่า init
        // solver จึงเริ่มจากสถานะที่ล็อกช่องไว้แล้วโดยไม่เคยมีใครขอ
        // บังคับให้ผ่านรีเซ็ตก่อนหนึ่งไซเคิล (rst_n เป็น async ค่าจึงถูกล้างทันที)
        reg f_init = 1'b1;
        always @(posedge clk) f_init <= 1'b0;
        always @(*) if (f_init) assume(!rst_n);

        // yosys+slang ยังไม่รองรับ $onehot/$onehot0 จึงเขียนเองด้วยเลขฐานสอง
        // v มีบิตเดียว <=> v != 0 และ (v & (v-1)) == 0
        function automatic bit f_onehot0(input logic [15:0] v);
            f_onehot0 = ((v & (v - 16'd1)) == 16'd0);
        endfunction
        function automatic bit f_onehot(input logic [15:0] v);
            f_onehot = (v != 16'd0) && ((v & (v - 16'd1)) == 16'd0);
        endfunction

        // ---------------------------------------------------------
        // สมมติฐานฝั่งต้นทางของทั้ง 5 พอร์ต (AXI4-Stream + tid one-hot)
        // ---------------------------------------------------------
        generate
            for (genvar p = 0; p < 5; p++) begin : f_src
                always @(*) begin
                    if (rst_n && s_valid[p]) begin
                        assume(f_onehot(s_tid[p]));
                        assume((s_tid[p] & ~s_ready[p]) == '0);
                    end
                end
            end
        endgenerate

        // ---------------------------------------------------------
        // ทราฟฟิกที่ถูกรูปแบบ: ทุก flit ในแพกเกจเดียวกันต้องจ่าหน้าที่เดียวกัน
        //
        // ข้อนี้ *ต้องมี* ไม่ใช่เพื่อความสวยงาม: ถ้าไม่ assume solver จะสร้างเคส
        // ที่หัวคิวเปลี่ยนปลายทางกลางแพกเกจขณะที่ arbiter ยังล็อกช่องอยู่ แล้ว
        // crossbar จะคาย flit นั้นออกพอร์ตเดิม = ส่งผิดทาง (พบเป็น counterexample
        // ของ assert_grant_matches_route_vc0 ที่ out=NORTH in=WEST จริงๆ)
        //
        // router เองไม่ได้บังคับข้อนี้ และยังคงเป็น assume ที่นี่ เพราะขา s_* ของ
        // router เป็นสายภายในของเมช ตัวที่บังคับจริงคือ noc_mesh_2x2_vc หัวข้อ 2.3
        // (ตั้งแต่ 2026-09-12): ที่ขาเข้า LOCAL ทุกโหนด flit ที่จ่าหน้าไม่ตรงหัว
        // แพกเกจที่เปิดอยู่บน VC เดียวกันถูกทิ้ง + dest_err + ปิดแพกเกจค้าง และ
        // formal ของเมชพิสูจน์ assert_local_dest_stable โดยไม่ assume แล้ว
        // ลิงก์ระหว่าง router ได้ข้อนี้มาโดยโครงสร้าง (router ส่งต่อทีละแพกเกจ)
        // ก่อนหน้านั้น master ที่สลับ tdest กลางแพกเกจจะทำให้ router ส่งผิดทาง
        // แบบเงียบๆ ไม่มีธง และ arbiter ปลดล็อกได้ก็ต่อเมื่อครบ STALL_MAX
        // ---------------------------------------------------------
        generate
            for (genvar p = 0; p < 5; p++) begin : f_wf
                for (genvar vc = 0; vc < NUM_VCS; vc++) begin : f_wf_vc
                    logic       f_in_pkt;
                    logic [3:0] f_in_dest;
                    wire f_acc = s_valid[p] && s_tid[p][vc] && s_ready[p][vc];

                    always_ff @(posedge clk or negedge rst_n) begin
                        if (!rst_n) begin
                            f_in_pkt <= 1'b0;
                        end else if (f_acc) begin
                            if (s_tlast[p]) begin
                                f_in_pkt <= 1'b0;
                            end else begin
                                f_in_pkt  <= 1'b1;
                                f_in_dest <= s_tdest[p];
                            end
                        end
                    end

                    always @(*) begin
                        if (rst_n && f_in_pkt && s_valid[p] && s_tid[p][vc])
                            assume(s_tdest[p] == f_in_dest);
                    end
                end
            end
        endgenerate

        // ---------------------------------------------------------
        // 1. ตัวถอด XY
        // ---------------------------------------------------------
        generate
            for (genvar ip = 0; ip < 5; ip++) begin : f_route_in
                for (genvar vc = 0; vc < NUM_VCS; vc++) begin : f_route_vc
                    always @(*) begin
                        if (rst_n && f_past_valid) begin
                            // ขอออกได้พอร์ตเดียวเป๊ะ ไม่ขอเลยก็ได้ แต่ห้ามสองพอร์ต
                            assert_route_onehot:
                                assert(f_onehot0(route_req[ip][vc]));

                            // มี flit เมื่อไหร่ต้องมีปลายทางเสมอ ไม่มี flit ก็ห้ามขอ
                            // ผิดข้อนี้ = flit ค้างในบัฟเฟอร์ตลอดกาล (ไม่มีใครมารับ)
                            // หรือ arbiter ถูกปลุกด้วยคำขอผี
                            assert_route_iff_valid:
                                assert((|route_req[ip][vc]) == buf_valid[ip][vc]);

                            if (buf_valid[ip][vc]) begin
                                if (buf_tdest[ip][vc][3:2] == MY_X &&
                                    buf_tdest[ip][vc][1:0] == MY_Y) begin
                                    // ถึงบ้านแล้วต้องเด้งออก LOCAL ไม่งั้นวนในเมชไม่จบ
                                    assert_eject_here:
                                        assert(route_req[ip][vc][LOCAL]);
                                end else begin
                                    // ยังไม่ถึงบ้านห้ามเด้งออก LOCAL แพกเกจของคนอื่น
                                    // จะถูกกินหายไปที่ node นี้
                                    assert_no_false_eject:
                                        assert(!route_req[ip][vc][LOCAL]);
                                end
                            end
                        end
                    end
                end
            end
        endgenerate

        // ---------------------------------------------------------
        // 2. Crossbar
        // ---------------------------------------------------------
        generate
            for (genvar op = 0; op < 5; op++) begin : f_out
                always @(*) begin
                    if (rst_n && f_past_valid) begin
                        // เงื่อนไขที่ AND-OR mux ต้องมี ไม่งั้นข้อมูลถูก OR ปนกัน
                        // ครอบทั้งข้าม input และข้าม VC (สายส่งออกมีเส้นเดียว)
                        assert_xbar_onehot:
                            assert(f_onehot0({grant_vc0[op], grant_vc1[op]}));

                        // ห้ามมี valid ออกไปโดยไม่มีใครได้ grant
                        assert_no_valid_without_grant:
                            assert(!m_valid[op] ||
                                   (|grant_vc0[op]) || (|grant_vc1[op]));

                        // ป้าย VC ที่ติดไปกับ flit ต้องตรงกับ VC ที่ได้ grant จริง
                        // ผิดข้อนี้ = flit ข้ามเลนตอนออกจาก router ปลายทางจับผิดคิว
                        if (NUM_VCS == 2) begin
                            if (|grant_vc1[op])
                                assert_tid_vc1:  assert(m_tid[op] == 2'b10);
                            else if (|grant_vc0[op])
                                assert_tid_vc0:  assert(m_tid[op] == 2'b01);
                            else
                                assert_tid_idle: assert(m_tid[op] == 2'b00);
                        end
                    end
                end

                for (genvar ip = 0; ip < 5; ip++) begin : f_xbar_in
                    always @(*) begin
                        if (rst_n && f_past_valid) begin
                            // grant ต้องมาจากคนที่ขอออกพอร์ตนี้จริง = ไม่ส่งผิดทาง
                            // และของที่คายออกต้องเป็นของคนนั้นเป๊ะ ไม่ใช่ OR ของหลายคน
                            if (grant_vc0[op][ip] && buf_valid[ip][0]) begin
                                assert_grant_matches_route_vc0: assert(route_req[ip][0][op]);
                                assert_xbar_data_vc0:  assert(m_tdata[op] == buf_tdata[ip][0]);
                                assert_xbar_dest_vc0:  assert(m_tdest[op] == buf_tdest[ip][0]);
                                assert_xbar_last_vc0:  assert(m_tlast[op] == buf_tlast[ip][0]);
                                assert_xbar_valid_vc0: assert(m_valid[op]);
                            end
                            if (grant_vc1[op][ip] && buf_valid[ip][1]) begin
                                assert_grant_matches_route_vc1: assert(route_req[ip][1][op]);
                                assert_xbar_data_vc1:  assert(m_tdata[op] == buf_tdata[ip][1]);
                                assert_xbar_dest_vc1:  assert(m_tdest[op] == buf_tdest[ip][1]);
                                assert_xbar_last_vc1:  assert(m_tlast[op] == buf_tlast[ip][1]);
                                assert_xbar_valid_vc1: assert(m_valid[op]);
                            end
                        end
                    end
                end
            end
        endgenerate

        // ---------------------------------------------------------
        // 3. input buffer หนึ่งตัวห้ามถูก grant จากสองพอร์ตออกพร้อมกัน
        //    (เหตุผลเต็มอยู่หัวบล็อก นี่คือทางที่ flit จะถูกโคลน)
        // ---------------------------------------------------------
        generate
            for (genvar ip = 0; ip < 5; ip++) begin : f_fanout
                logic [4:0] gcol0, gcol1;
                always @(*) begin
                    for (int op = 0; op < 5; op++) begin
                        gcol0[op] = grant_vc0[op][ip];
                        gcol1[op] = grant_vc1[op][ip];
                    end
                end

                always @(*) begin
                    if (rst_n && f_past_valid) begin
                        assert_no_grant_fanout_vc0: assert(f_onehot0(gcol0));
                        assert_no_grant_fanout_vc1: assert(f_onehot0(gcol1));

                        // credit ตีกลับได้เฉพาะตอนมีคนรับจริง ไม่งั้น FIFO ถูกอ่านทิ้ง
                        assert_ready_needs_grant_vc0: assert(!buf_ready[ip][0] || (|gcol0));
                        assert_ready_needs_grant_vc1: assert(!buf_ready[ip][1] || (|gcol1));
                    end
                end
            end
        endgenerate

        // -------------------------------------------------------------
        // COVER: พิสูจน์ว่า router เดินได้จริง ไม่ใช่ผ่านเพราะไม่มีอะไรเกิดขึ้น
        // -------------------------------------------------------------
        always @(posedge clk) begin
            if (f_past_valid && $past(rst_n) && rst_n) begin
                cover_eject_local:  cover(m_valid[LOCAL] && m_ready[LOCAL][0]);
                cover_forward_east: cover(m_valid[EAST]);
                cover_turn_xy:      cover(m_valid[NORTH] || m_valid[SOUTH]);

                // สองพอร์ตออกทำงานพร้อมกัน = crossbar ขนานได้จริง ไม่ใช่ทางเดี่ยว
                cover_two_outputs:  cover(m_valid[EAST] && m_valid[LOCAL]);

                // สอง VC วิ่งพร้อมกันคนละพอร์ต
                cover_both_vcs:     cover((|grant_vc0[EAST]) && (|grant_vc1[LOCAL]));
            end
        end
    `endif
    `endif

endmodule
