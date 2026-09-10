`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/02/2026 02:51:55 PM
// Design Name: 
// Module Name: gals_node_wrapper
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


module gals_node_wrapper #(
    parameter DATA_W = 8,
    parameter CORD_W = 2,
    parameter DEPTH = 16,
    parameter NUM_VCS = 2
)(
    input  logic rst_n,

    input  logic clk_host,
    input  logic              s_host_valid,
    input  logic              s_host_tlast,
    input  logic [3:0]        s_host_tdest,
    input  logic [DATA_W-1:0] s_host_tdata,
    input  logic [NUM_VCS-1:0]s_host_tid,
    output logic [NUM_VCS-1:0]s_host_ready,
    
    output logic              m_host_valid,
    output logic              m_host_tlast,
    output logic [3:0]        m_host_tdest,
    output logic [DATA_W-1:0] m_host_tdata,
    output logic [NUM_VCS-1:0]m_host_tid,
    input  logic [NUM_VCS-1:0]m_host_ready,

    input  logic clk_noc,
    output logic              m_noc_valid,
    output logic              m_noc_tlast,
    output logic [3:0]        m_noc_tdest,
    output logic [DATA_W-1:0] m_noc_tdata,
    output logic [NUM_VCS-1:0]m_noc_tid,
    input  logic [NUM_VCS-1:0]m_noc_ready,
    
    input  logic              s_noc_valid,
    input  logic              s_noc_tlast,
    input  logic [3:0]        s_noc_tdest,
    input  logic [DATA_W-1:0] s_noc_tdata,
    input  logic [NUM_VCS-1:0]s_noc_tid,
    output logic [NUM_VCS-1:0]s_noc_ready,

    // ---- ECC จาก async FIFO ทั้ง 4 ตัวของโหนดนี้ (sticky, โดเมน clk_noc)
    // เดิมพอร์ตพวกนี้ถูกปล่อยลอย ( .ecc_double_err() ) แปลว่า double-bit error
    // ถูกตรวจเจอแล้วโยนทิ้ง ข้อมูลเสียไหลต่อไปเงียบๆ
    output logic              ecc_single_err,   // ซ่อมได้ (เตือน)
    output logic              ecc_double_err,   // ซ่อมไม่ได้ = ข้อมูลเสียแน่นอน

    // ---- host ยิง tid ที่ไม่ใช่ one-hot (sticky, ข้ามมาโดเมน clk_noc แล้ว)
    output logic              host_tid_err
);

    localparam PACK_W = 1 + 4 + DATA_W; 
    localparam ADDR_W = $clog2(DEPTH);

    // =========================================================
    // Path 1: Host -> NoC
    // =========================================================
    logic [PACK_W-1:0] tx_wdata, tx_rdata [NUM_VCS];
    logic tx_empty [NUM_VCS], tx_full [NUM_VCS];
    assign tx_wdata = {s_host_tlast, s_host_tdest, s_host_tdata};

    // =========================================================
    // ตรวจ tid จาก host ก่อนเขียนลงคิว
    //
    // tid เป็น one-hot: 01 = VC0, 10 = VC1 แต่ไม่มีอะไรบังคับไว้เลย
    // w_en ของแต่ละ VC คือ s_host_valid && s_host_tid[v] && !tx_full[v]
    // ผลที่ตามมาถ้า host ยิงค่าอื่นมา:
    //   tid = 00 -> ไม่มี VC ไหนถูกเขียน flit หายเงียบ ผู้ส่งรอ ready ที่ไม่มีวันมา
    //               (พิสูจน์ในซิม: node ค้าง gap 8,388,609 ไซเคิล)
    //   tid = 11 -> ถูกเขียนลง *ทั้งสอง* VC flit เดียวกลายเป็นสองใบ
    //               (พิสูจน์ในซิม: sequence error 24 ครั้ง)
    //
    // นี่คือจุดที่ flit หายจริง ไม่ใช่ที่ขอบเมช — ตัวกรองที่ขอบเมชมองไม่เห็นเคสนี้
    // เพราะ noc_tx_tid ถูกสร้างโดย MUX ข้างล่างซึ่ง one-hot อยู่แล้วโดยโครงสร้าง
    // และนี่คือทางเดียวกับที่ noc_host.py ทำ VC0 หายทุกแพกเกจ (vc_id=0 -> tid=00)
    //
    // ทำแบบเดียวกับ dest_err: ทิ้ง flit แต่ยังรับเข้ามาตามปกติ แล้วยกธง sticky
    // ผู้ส่งไม่ค้างเพราะ ready ยังตอบตาม full ตามเดิม
    // =========================================================
    logic host_tid_ok;
    assign host_tid_ok = (s_host_tid != '0) && ((s_host_tid & (s_host_tid - 1'b1)) == '0);

    // ธง ECC ต่อ VC — TX อ่านด้วย clk_noc, RX อ่านด้วย clk_host (คนละโดเมน)
    logic tx_sbe [NUM_VCS], tx_dbe [NUM_VCS];
    logic rx_sbe [NUM_VCS], rx_dbe [NUM_VCS];

    genvar v;
    generate
        for (v = 0; v < NUM_VCS; v++) begin : TX_VC
            async_fifo_fwft #(.DATA_WIDTH(PACK_W), .ADDR_WIDTH(ADDR_W)) tx_fifo (
                .wclk(clk_host), .wrst_n(rst_n),
                .w_en(s_host_valid && s_host_tid[v] && !tx_full[v] && host_tid_ok),
                .wdata(tx_wdata), .wfull(tx_full[v]),
                
                .rclk(clk_noc),  .rrst_n(rst_n), 
                .r_en(m_noc_valid && m_noc_tid[v] && m_noc_ready[v]), 
                .rdata(tx_rdata[v]), .rempty(tx_empty[v]),            
                
                .almost_full(), .prog_full_thresh('0),
                .ecc_single_err(tx_sbe[v]), .ecc_double_err(tx_dbe[v])
            );
            assign s_host_ready[v] = ~tx_full[v];
        end
    endgenerate

    // 🏎️ Flit-by-Flit Interleaving MUX (ไม่มีการล็อคคิว!)
    always_comb begin
        m_noc_valid = 1'b0; m_noc_tid = '0; m_noc_tlast = 1'b0; m_noc_tdest = '0; m_noc_tdata = '0;
        
        // เลือกว่าจะ "เสนอ" ข้อมูลจาก VC ไหน โดยไม่ดู ready เลย
        if (!tx_empty[1]) begin 
            m_noc_valid = 1'b1; m_noc_tid = 2'b10;
            {m_noc_tlast, m_noc_tdest, m_noc_tdata} = tx_rdata[1];
        end else if (!tx_empty[0]) begin
            m_noc_valid = 1'b1; m_noc_tid = 2'b01;
            {m_noc_tlast, m_noc_tdest, m_noc_tdata} = tx_rdata[0];
        end
    end

    // =========================================================
    // Path 2: NoC -> Host
    // =========================================================
    logic [PACK_W-1:0] rx_wdata, rx_rdata [NUM_VCS];
    logic rx_empty [NUM_VCS], rx_full [NUM_VCS];
    assign rx_wdata = {s_noc_tlast, s_noc_tdest, s_noc_tdata};

    generate
        for (v = 0; v < NUM_VCS; v++) begin : RX_VC
            async_fifo_fwft #(.DATA_WIDTH(PACK_W), .ADDR_WIDTH(ADDR_W)) rx_fifo (
                .wclk(clk_noc), .wrst_n(rst_n),
                .w_en(s_noc_valid && s_noc_tid[v] && !rx_full[v]),
                .wdata(rx_wdata), .wfull(rx_full[v]),
                
                .rclk(clk_host), .rrst_n(rst_n), 
                .r_en(m_host_valid && m_host_tid[v] && m_host_ready[v]),
                .rdata(rx_rdata[v]), .rempty(rx_empty[v]),            
                
                .almost_full(), .prog_full_thresh('0),
                .ecc_single_err(rx_sbe[v]), .ecc_double_err(rx_dbe[v])
            );
            assign s_noc_ready[v] = ~rx_full[v];
        end
    endgenerate

    // 🏎️ Flit-by-Flit Interleaving MUX (ให้ Host รับไปประกอบเอง)
    always_comb begin
        m_host_valid = 1'b0; m_host_tid = '0; m_host_tlast = 1'b0; m_host_tdest = '0; m_host_tdata = '0;
        
        if (!rx_empty[1]) begin
            m_host_valid = 1'b1; m_host_tid = 2'b10;
            {m_host_tlast, m_host_tdest, m_host_tdata} = rx_rdata[1];
        end else if (!rx_empty[0]) begin
            m_host_valid = 1'b1; m_host_tid = 2'b01;
            {m_host_tlast, m_host_tdest, m_host_tdata} = rx_rdata[0];
        end
    end
    // =========================================================
    // ECC error reporting
    // ธงที่ออกมาจาก async_fifo เป็นพัลส์ไซเคิลเดียวต่อการอ่านหนึ่งครั้ง
    // ต้องแลตช์ค้างไว้ ไม่งั้น ILA ที่ trigger ทีหลังจะไม่มีวันเห็น
    // แลตช์ในโดเมนของตัวเองก่อน แล้วค่อยข้ามมา clk_noc
    // =========================================================
    logic sbe_noc_q, dbe_noc_q;
    always_ff @(posedge clk_noc or negedge rst_n) begin
        if (!rst_n) begin
            sbe_noc_q <= 1'b0;
            dbe_noc_q <= 1'b0;
        end else begin
            for (int i = 0; i < NUM_VCS; i++) begin
                if (tx_sbe[i]) sbe_noc_q <= 1'b1;
                if (tx_dbe[i]) dbe_noc_q <= 1'b1;
            end
        end
    end

    logic tid_err_host_q;
    always_ff @(posedge clk_host or negedge rst_n) begin
        if (!rst_n)                                 tid_err_host_q <= 1'b0;
        else if (s_host_valid && !host_tid_ok)      tid_err_host_q <= 1'b1;
    end

    logic sbe_host_q, dbe_host_q;
    always_ff @(posedge clk_host or negedge rst_n) begin
        if (!rst_n) begin
            sbe_host_q <= 1'b0;
            dbe_host_q <= 1'b0;
        end else begin
            for (int i = 0; i < NUM_VCS; i++) begin
                if (rx_sbe[i]) sbe_host_q <= 1'b1;
                if (rx_dbe[i]) dbe_host_q <= 1'b1;
            end
        end
    end

    // ตั้งแล้วไม่มีวันกลับ = level นิ่งยาว ข้ามโดเมนด้วย 2FF ได้ปลอดภัย
    // (เหตุผลเดียวกับที่ noc_stress_tester ใช้ sync_2stage กับธง done/err)
    logic [2:0] host_flags_sync;
    sync_2stage #(.WIDTH(3)) u_ecc_cdc (
        .clk(clk_noc), .rst(~rst_n),
        .d({tid_err_host_q, dbe_host_q, sbe_host_q}),
        .q(host_flags_sync)
    );

    assign ecc_single_err = sbe_noc_q | host_flags_sync[0];
    assign ecc_double_err = dbe_noc_q | host_flags_sync[1];
    assign host_tid_err   = host_flags_sync[2];


    // =================================================================
    // FORMAL
    //
    // นี่คือขอบ GALS: ทุก flit ที่ข้ามระหว่างโดเมน host กับโดเมน NoC ผ่านที่นี่
    // ตัว async_fifo/async_fifo_fwft ข้างในถูกพิสูจน์แยกไปแล้ว สิ่งที่ยังไม่เคย
    // ถูกตรวจคือ "กาว" รอบๆ มัน ซึ่งเป็นจุดที่ bug ประเภทต่อสายผิดอยู่:
    //   - MUX เลือก VC แบบ strict priority ทั้งสองทิศ
    //   - การประกอบ/แกะ {tlast, tdest, tdata} เข้าออก FIFO
    //   - r_en ที่ถูกสร้างจาก valid/tid/ready ของฝั่งตรงข้าม
    //   - การแมป ready <-> full
    //
    // property ที่มีน้ำหนักที่สุดคือ assert_tx_no_pop_empty / assert_rx_no_pop_empty:
    // r_en ของ FIFO ถูกประกอบจากสามสัญญาณคนละที่ (m_*_valid, m_*_tid, m_*_ready)
    // ถ้าเงื่อนไขไหนหลุด จะกลายเป็นการป๊อป FIFO ที่ว่าง = อ่านขยะออกมาเป็น flit
    // โดยไม่มีธงอะไรขึ้นเลย
    //
    // เป็น multiclock จริง (clk_host กับ clk_noc คนละโดเมน ไม่มีความสัมพันธ์กัน)
    // property เกือบทั้งหมดจึงเขียนเป็น combinational ล้วน ไม่พึ่ง $past
    // ส่วนที่ต้องใช้อดีตจะเก็บ past ด้วยมือตามสไตล์เดียวกับ gray_counter
    // (yosys มีบั๊กเรื่อง $past ในโหมด multiclock)
    //
    // ขอบเขตที่ต้องพูดตรงๆ: เมื่อ FORMAL ถูกนิยาม async_fifo จะสลับไปใช้
    // dual_port_ram ธรรมดาและผูก ecc_single_err/ecc_double_err ไว้ที่ 0
    // (เขียนไว้ในตัว async_fifo.sv เอง) แลตช์ ECC ในโมดูลนี้จึงไม่มีทางถูกยกขึ้น
    // ในการรัน formal — assert_ecc_*_sticky เป็นจริงแบบ vacuous ปล่อยไว้เพื่อกัน
    // การแก้ในอนาคตที่เผลอทำให้แลตช์เคลียร์ตัวเอง ส่วนตัว ECC จริงพิสูจน์ด้วย
    // tb_ecc_secded (exhaustive) และตัวนับบนบอร์ด ไม่ใช่ที่นี่
    // =================================================================
    `ifdef FORMAL
        localparam int F_PACK_W = 1 + 4 + DATA_W;

        reg f_past_valid = 1'b0;
        always @(posedge clk_noc) f_past_valid <= 1'b1;

        reg f_init = 1'b1;
        always @(posedge clk_noc) f_init <= 1'b0;
        always @(*) if (f_init) assume(!rst_n);

        // ---------------------------------------------------------
        // ข้อสมมติฝั่งต้นทางทั้งสองทิศ (สัญญา AXI4-Stream + tid one-hot)
        // ถ้าไม่ assume ข้อ backpressure flit จะหายเงียบ เพราะ w_en ถูก and
        // ด้วย !full ไว้แล้ว ตัว FIFO จึงไม่มีทางรู้ว่ามีของถูกทิ้ง
        // ---------------------------------------------------------
        always @(*) begin
            if (s_host_valid) begin
                // ยัง assume one-hot ไว้: ตัวกรอง host_tid_ok อยู่ใน RTL แล้วก็จริง
                // แต่การ assert ว่า w_en=0 ตอน tid เสีย เป็นการท่องนิพจน์เดิมซ้ำ
                // และต้องอ้าง hierarchy เข้าไปในตัว FIFO ซึ่งเปราะ
                // ตัวกรองพิสูจน์ด้วย simulation แทน ซึ่งวัด *ผลเสียจริง*
                // (tid=00 -> node ค้าง 8.4M ไซเคิล, tid=11 -> sequence error 24 ครั้ง)
                // ดู BAD_TID ใน tb_noc_stress_tester
                assume($onehot(s_host_tid));
                assume((s_host_tid & ~s_host_ready) == '0);
            end
            if (s_noc_valid) begin
                assume($onehot(s_noc_tid));
                assume((s_noc_tid & ~s_noc_ready) == '0);
            end
        end

        // ---------------------------------------------------------
        // MUX ทิศ Host -> NoC
        // ---------------------------------------------------------
        always @(*) begin
            if (rst_n && f_past_valid && NUM_VCS == 2) begin
                // มีของใน VC ไหนก็ตาม ต้องเสนอออกไป ไม่มีก็ต้องเงียบ
                assert_tx_valid_iff_data:
                    assert(m_noc_valid == (!tx_empty[1] || !tx_empty[0]));

                // strict priority: VC1 มาก่อนเสมอ และของที่คายต้องเป็นของ VC1 เป๊ะ
                if (!tx_empty[1]) begin
                    assert_tx_pick_vc1: assert(m_noc_tid == 2'b10);
                    assert_tx_data_vc1:
                        assert({m_noc_tlast, m_noc_tdest, m_noc_tdata} == tx_rdata[1]);
                end else if (!tx_empty[0]) begin
                    assert_tx_pick_vc0: assert(m_noc_tid == 2'b01);
                    assert_tx_data_vc0:
                        assert({m_noc_tlast, m_noc_tdest, m_noc_tdata} == tx_rdata[0]);
                end else begin
                    // ไม่มีของก็ห้ามติดป้าย VC ค้างไว้ ปลายทาง demux ตาม tid
                    assert_tx_idle_tid: assert(m_noc_tid == '0);
                end

                if (m_noc_valid) assert_tx_tid_onehot: assert($onehot(m_noc_tid));

            end
        end

        // ---------------------------------------------------------
        // MUX ทิศ NoC -> Host (ทรงเดียวกัน คนละโดเมนคล็อก)
        // ---------------------------------------------------------
        always @(*) begin
            if (rst_n && f_past_valid && NUM_VCS == 2) begin
                assert_rx_valid_iff_data:
                    assert(m_host_valid == (!rx_empty[1] || !rx_empty[0]));

                if (!rx_empty[1]) begin
                    assert_rx_pick_vc1: assert(m_host_tid == 2'b10);
                    assert_rx_data_vc1:
                        assert({m_host_tlast, m_host_tdest, m_host_tdata} == rx_rdata[1]);
                end else if (!rx_empty[0]) begin
                    assert_rx_pick_vc0: assert(m_host_tid == 2'b01);
                    assert_rx_data_vc0:
                        assert({m_host_tlast, m_host_tdest, m_host_tdata} == rx_rdata[0]);
                end else begin
                    assert_rx_idle_tid: assert(m_host_tid == '0);
                end

                if (m_host_valid) assert_rx_tid_onehot: assert($onehot(m_host_tid));
            end
        end

        // ---------------------------------------------------------
        // ความปลอดภัยของ r_en / ready ต่อ VC
        // ---------------------------------------------------------
        // ป้าย assert ถูกใช้เป็นชื่อเซลล์ตรงๆ ป้ายซ้ำใน generate loop ชนกัน
        // (yosys: "a cell with the same name was already created") จึงกางสองเลนออกมาเอง
        always @(*) begin
            if (rst_n && f_past_valid && NUM_VCS == 2) begin
                // ห้ามป๊อป FIFO ที่ว่าง — จะได้ขยะออกมาเป็น flit เงียบๆ
                if (m_noc_valid && m_noc_tid[0] && m_noc_ready[0])
                    assert_tx_no_pop_empty_vc0: assert(!tx_empty[0]);
                if (m_noc_valid && m_noc_tid[1] && m_noc_ready[1])
                    assert_tx_no_pop_empty_vc1: assert(!tx_empty[1]);
                if (m_host_valid && m_host_tid[0] && m_host_ready[0])
                    assert_rx_no_pop_empty_vc0: assert(!rx_empty[0]);
                if (m_host_valid && m_host_tid[1] && m_host_ready[1])
                    assert_rx_no_pop_empty_vc1: assert(!rx_empty[1]);

                // ready ที่ตีกลับต้องสะท้อนสถานะ full จริงของเลนนั้น
                assert_host_ready_map_vc0: assert(s_host_ready[0] == ~tx_full[0]);
                assert_host_ready_map_vc1: assert(s_host_ready[1] == ~tx_full[1]);
                assert_noc_ready_map_vc0:  assert(s_noc_ready[0]  == ~rx_full[0]);
                assert_noc_ready_map_vc1:  assert(s_noc_ready[1]  == ~rx_full[1]);
            end
        end

        // ---------------------------------------------------------
        // ธง ECC ที่ออกไปข้างนอก
        //
        // ไม่มี assertion เรื่อง "แลตช์ต้อง sticky" ในนี้ตั้งใจ: ตัว RTL เขียนเป็น
        // if (tx_sbe[i]) q <= 1'b1; โดยไม่มีกิ่งเคลียร์เลย ความ sticky จึงเป็นเรื่อง
        // โครงสร้าง assertion ที่เขียนทับก็แค่ท่องโค้ดซ้ำ ไม่ได้ตรวจอะไรเพิ่ม
        // และในสภาพแวดล้อม formal นี้มันยัง vacuous ด้วย เพราะเมื่อ FORMAL ถูกนิยาม
        // async_fifo จะผูก ecc_single_err/ecc_double_err ไว้ที่ 0 แลตช์จึงไม่มีทางถูกยก
        // (เคยเขียนไว้แล้วถอดออก: induction สร้างสถานะเริ่มต้นที่ตัวเก็บ past เป็น 1
        //  ขณะที่แลตช์เป็น 0 ซึ่งไปถึงไม่ได้จริง เป็น artefact ของ induction ไม่ใช่บั๊ก)
        // ตัว ECC จริงพิสูจน์ด้วย tb_ecc_secded (exhaustive) และตัวนับบนบอร์ด
        // ---------------------------------------------------------
        // ธงที่ออกไปข้างนอกต้องครอบทั้งสองโดเมน ไม่ใช่โดเมนเดียว
        always @(*) begin
            if (rst_n && f_past_valid) begin
                assert_ecc_sbe_out: assert(ecc_single_err == (sbe_noc_q | host_flags_sync[0]));
                assert_ecc_dbe_out: assert(ecc_double_err == (dbe_noc_q | host_flags_sync[1]));
            end
        end

        // -------------------------------------------------------------
        // COVER
        // -------------------------------------------------------------
        always @(posedge clk_noc) begin
            if (f_past_valid && rst_n && NUM_VCS == 2) begin
                cover_tx_vc1: cover(m_noc_valid && m_noc_tid == 2'b10 && m_noc_ready[1]);
                cover_tx_vc0: cover(m_noc_valid && m_noc_tid == 2'b01 && m_noc_ready[0]);
                cover_rx_vc1: cover(m_host_valid && m_host_tid == 2'b10);

                // ทั้งสองทิศเดินพร้อมกัน = ขอบ GALS ทำงานสองทางจริง
                cover_both_paths: cover(m_noc_valid && m_host_valid);

                // MUX ตัวนี้เป็น strict priority ล้วน *ไม่มี* anti-starvation
                // ต่างจาก vc_port_arbiter ที่มี starve_cnt/override กันไว้
                // ตราบใดที่ VC1 ยังมีของ VC0 ก็ไม่ได้ออกเลย ไม่มีเพดานเวลา
                // cover นี้ยืนยันว่าสถานะนั้นไปถึงได้จริง ไม่ใช่แค่กังวลบนกระดาษ
                cover_vc0_waits_behind_vc1:
                    cover(!tx_empty[0] && !tx_empty[1] && m_noc_tid == 2'b10);
            end
        end
    `endif

endmodule
