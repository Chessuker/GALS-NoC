`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: tb_noc_stress_tester
//
// จำลอง "ชุดเดียวกับที่รันบนบอร์ด" — gals_noc_top + noc_stress_tester
// ที่อัตราส่วนนาฬิกาจริงของ Arty (MMCM VCO 1000 MHz)
//
// ทำไมถึงต้องมี:
//   tb_noc_mesh_2x2_gals ใช้ traffic_gen ซึ่งเป็นคนละโมดูลกับ traffic_node_agent
//   ที่ใช้จริงบนบอร์ด แปลว่าโครงสร้าง stress ทั้งชุดไม่เคยถูกจำลองเลยสักครั้ง
//   ตัวเลขทุกอย่างของมันมาจากบอร์ดล้วนๆ — พอ watchdog false-trip จึงไม่มีที่ให้ไล่
//   ของจริงติดที่ 2^24 cycle x 4 โดเมน = 0.2 วินาที จำลองไม่ไหว
//   ตอนนี้ noc_stress_tester รับ WINDOW_LOG แล้ว จึงย่อลงมาจำลองได้
//
// เป้าหมายหลัก: วัด max_gap ของจริง เพื่อตั้ง STUCK_LOG จากข้อมูล ไม่ใช่เดา
//   ตั้ง STUCK_LOG ใหญ่ไว้ก่อน (ไม่ให้ trip) แล้วอ่านว่าช่องว่างจริงยาวเท่าไร
//////////////////////////////////////////////////////////////////////////////////

module tb_noc_stress_tester;

    // ---- อัตราส่วนนาฬิกาเดียวกับบอร์ด (ครึ่งคาบ, ns)
    localparam real HP_NOC = 6.25;   // 80.00 MHz  clk_out1
    localparam real HP_H00 = 5.00;   // 100.00 MHz clk_out2
    localparam real HP_H01 = 7.00;   // 71.43 MHz  clk_out3
    localparam real HP_H10 = 6.00;   // 83.33 MHz  clk_out4
    localparam real HP_H11 = 7.00;   // 71.43 MHz  clk_out5

    // ---- ย่อ window ลง แต่ให้ยาวพอที่ contention จะเข้าสู่สภาวะคงตัว
    //      2^18 cycle @80MHz ~ 3.3 ms  (regression เดิมจำลอง 5 ms ใช้เวลา ~40 s)
    localparam int WINDOW_LOG = 18;
    localparam int WARMUP_LOG = 8;
    localparam int DRAIN_LOG  = 8;
    // ตั้งเกณฑ์ให้ใหญ่จนไม่มีทาง trip — รอบนี้เรามาวัด ไม่ได้มาตัดสิน
    localparam int STUCK_LOG  = 23;
    localparam int GAP_W      = 24;

    // PATTERN/VC_MODE override ได้จาก command line: xelab -generic_top "PATTERN=0"
    parameter int PATTERN = 1;
    parameter int VC_MODE = 2;

    logic clk_noc = 0, clk_h00 = 0, clk_h01 = 0, clk_h10 = 0, clk_h11 = 0;
    logic rst_n;

    always #(HP_NOC) clk_noc = ~clk_noc;
    always #(HP_H00) clk_h00 = ~clk_h00;
    always #(HP_H01) clk_h01 = ~clk_h01;
    always #(HP_H10) clk_h10 = ~clk_h10;
    always #(HP_H11) clk_h11 = ~clk_h11;

    //=====================================================================
    // สายสัญญาณ (ผังเดียวกับ arty_stress_top)
    //=====================================================================
    logic [7:0] t00_tx_tdata, t01_tx_tdata, t10_tx_tdata, t11_tx_tdata;
    logic [3:0] t00_tx_tdest, t01_tx_tdest, t10_tx_tdest, t11_tx_tdest;
    logic [1:0] t00_tx_tid,   t01_tx_tid,   t10_tx_tid,   t11_tx_tid;
    logic       t00_tx_tlast, t01_tx_tlast, t10_tx_tlast, t11_tx_tlast;
    logic       t00_tx_tvalid,t01_tx_tvalid,t10_tx_tvalid,t11_tx_tvalid;
    logic [1:0] t00_tx_tready,t01_tx_tready,t10_tx_tready,t11_tx_tready;

    logic [7:0] t00_rx_tdata, t01_rx_tdata, t10_rx_tdata, t11_rx_tdata;
    logic [3:0] t00_rx_tdest, t01_rx_tdest, t10_rx_tdest, t11_rx_tdest;
    logic [1:0] t00_rx_tid,   t01_rx_tid,   t10_rx_tid,   t11_rx_tid;
    logic       t00_rx_tlast, t01_rx_tlast, t10_rx_tlast, t11_rx_tlast;
    logic       t00_rx_tvalid,t01_rx_tvalid,t10_rx_tvalid,t11_rx_tvalid;
    logic [1:0] t00_rx_tready,t01_rx_tready,t10_rx_tready,t11_rx_tready;

    gals_noc_top uut_noc_top (
        .clk_noc(clk_noc), .rst_n(rst_n),
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

    logic pass_g1, pass_g2, any_fail;

    noc_stress_tester #(
        .PATTERN(PATTERN), .VC_MODE(VC_MODE),
        .WINDOW_LOG(WINDOW_LOG), .WARMUP_LOG(WARMUP_LOG), .DRAIN_LOG(DRAIN_LOG),
        .STUCK_LOG(STUCK_LOG), .GAP_W(GAP_W)
    ) u_stress (
        .clk_h00(clk_h00), .clk_h01(clk_h01), .clk_h10(clk_h10), .clk_h11(clk_h11),
        .rst_n(rst_n),
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

    //=====================================================================
    // รายงาน
    //=====================================================================
    localparam int WINDOW = 1 << WINDOW_LOG;
    // วัดจริงได้สูงสุด 136 cycle (agent_10) เผื่อ ~15 เท่ากันความแปรปรวน
    localparam int GAP_MAX_OK = 2048;

    task automatic report(string nm, input int unsigned gap, input int unsigned txf,
                          input int unsigned rxf, input int unsigned errs,
                          input logic stuck, input real mhz);
        $display("  %-9s %7.2f  %12d %12d %10d %10d   %0d",
                 nm, mhz, txf, rxf, gap, errs, stuck);
    endtask

    // ---- จับว่าช่องว่างยาวๆ เกิดตอนไหนของ window และตอนนั้น agent อื่นอยู่สถานะอะไร
    //      (state: 0=WARMUP 1=RUN 2=DRAIN 3=DONE)
    // GEN_ARB[0] = LOCAL output ของ router idx0 = ทางเข้า node 00
    `define ARB0 uut_noc_top.uut_noc.ROW[0].COL[0].router.GEN_ARB[0].arb_inst
    // ---- นับ flit ที่ผ่านเข้า LOCAL port ของ idx0 (= ทางเข้า node 00) แยกตามขาเข้า
    //
    // จุดประสงค์: แยก "arbiter ยุติธรรมหรือเปล่า" ออกจาก "รูปทรง tree ทำให้ไม่เท่ากัน"
    //   สัดส่วนที่วัดได้ที่ตัว agent คือ 48 / 24 / 27 ซึ่งดูเหมือน agent_01 ได้เปรียบ
    //   แต่ที่ arbiter ตัวนี้มีขาเข้าแค่สองขาที่มีของ:
    //     EAST  (bit 3) = agent_01 ตัวเดียว
    //     NORTH (bit 1) = agent_10 + agent_11 ที่ merge กันมาแล้วตั้งแต่ idx2
    //   ถ้า round-robin ที่นี่ยุติธรรม EAST:NORTH ต้องราว 50:50
    //   แล้ว agent_10/11 ค่อยไปแบ่งครึ่งของ NORTH กันเองอีกชั้น -> 50/25/25
    //   ซึ่งตรงกับที่วัดได้ แปลว่าไม่ใช่บั๊กของ arbiter แต่เป็นรูปทรงของ tree
    //
    // นับเฉพาะไซเคิลที่ "ย้าย flit ได้จริง" (grant && valid && ready)
    //   grant เฉยๆ ไม่พอ เพราะตอน LOCKED มันค้าง grant ไว้ได้ทั้งที่ยังไม่มีของ
    localparam int LOCAL_P = 0, NORTH_P = 1, SOUTH_P = 2, EAST_P = 3, WEST_P = 4;
    int unsigned xfer_in [5] = '{default: 0};

    always @(posedge clk_noc) begin
        if (rst_n) begin
            for (int p = 0; p < 5; p++) begin
                if (`ARB0.grant_vc0[p] && `ARB0.valid_vc0[p] && `ARB0.ready_out_vc0)
                    xfer_in[p]++;
                if (`ARB0.grant_vc1[p] && `ARB0.valid_vc1[p] && `ARB0.ready_out_vc1)
                    xfer_in[p]++;
            end
        end
    end

    logic rep01 = 0, rep11 = 0;
    always @(posedge clk_h01) begin
        if (!rep01 && u_stress.agent_01.stuck_cnt == 20000) begin
            rep01 <= 1;
            $display("  [probe] t=%0t agent_01 gap=20000 win_cnt=%0d/%0d state 00=%0d 01=%0d 10=%0d 11=%0d",
                     $time, u_stress.agent_01.win_cnt, WINDOW,
                     u_stress.agent_00.state, u_stress.agent_01.state,
                     u_stress.agent_10.state, u_stress.agent_11.state);
            $display("          sink  : rx_tvalid=%0b rx_tready=%02b  (sink รับของอยู่ไหม)",
                     t00_rx_tvalid, t00_rx_tready);
            $display("          sender: tx_tvalid=%0b tx_tready=%02b tx_tid=%02b (agent_01 ถูกกั้นที่ไหน)",
                     t01_tx_tvalid, t01_tx_tready, t01_tx_tid);
            $display("          idx0 LOCAL arb_vc0: state=%0d locked_grant=%05b valid=%05b has_xfer=%0b",
                     `ARB0.arb_vc0.state, `ARB0.arb_vc0.locked_grant,
                     `ARB0.arb_vc0.valid,  `ARB0.arb_vc0.has_transferred);
            $display("          idx0 LOCAL arb_vc1: state=%0d locked_grant=%05b valid=%05b has_xfer=%0b",
                     `ARB0.arb_vc1.state, `ARB0.arb_vc1.locked_grant,
                     `ARB0.arb_vc1.valid,  `ARB0.arb_vc1.has_transferred);
        end
    end
    always @(posedge clk_h11) begin
        if (!rep11 && u_stress.agent_11.stuck_cnt == 20000) begin
            rep11 <= 1;
            $display("  [probe] t=%0t agent_11 gap=20000 win_cnt=%0d/%0d state 00=%0d 01=%0d 10=%0d 11=%0d",
                     $time, u_stress.agent_11.win_cnt, WINDOW,
                     u_stress.agent_00.state, u_stress.agent_01.state,
                     u_stress.agent_10.state, u_stress.agent_11.state);
        end
    end

    initial begin
        $display("\n=================================================");
        $display(" tb_noc_stress_tester  (PATTERN=%0d VC_MODE=%0d)", PATTERN, VC_MODE);
        $display(" WINDOW=2^%0d  STUCK=2^%0d (ตั้งสูงไว้เพื่อวัด ไม่ให้ trip)",
                 WINDOW_LOG, STUCK_LOG);
        $display("=================================================");

        rst_n = 0;
        repeat (40) @(posedge clk_noc);
        rst_n = 1;

        // รอจนทุก agent ถึง S_DONE
        wait (u_stress.agent_00.state == 2'd3 && u_stress.agent_01.state == 2'd3 &&
              u_stress.agent_10.state == 2'd3 && u_stress.agent_11.state == 2'd3);
        repeat (100) @(posedge clk_noc);

        $display("\n  %-9s %7s  %12s %12s %10s %10s   %s",
                 "agent", "clk MHz", "tx_flit", "rx_flit", "max_gap", "errors", "stuck");
        $display("  ---------------------------------------------------------------------------------");
        report("agent_00", u_stress.agent_00.max_gap, u_stress.agent_00.tx_flit_cnt,
               u_stress.agent_00.rx_vc0_cnt + u_stress.agent_00.rx_vc1_cnt,
               u_stress.agent_00.rx_err_cnt, u_stress.agent_00.stuck_seen, 1000.0/10.0);
        report("agent_01", u_stress.agent_01.max_gap, u_stress.agent_01.tx_flit_cnt,
               u_stress.agent_01.rx_vc0_cnt + u_stress.agent_01.rx_vc1_cnt,
               u_stress.agent_01.rx_err_cnt, u_stress.agent_01.stuck_seen, 1000.0/14.0);
        report("agent_10", u_stress.agent_10.max_gap, u_stress.agent_10.tx_flit_cnt,
               u_stress.agent_10.rx_vc0_cnt + u_stress.agent_10.rx_vc1_cnt,
               u_stress.agent_10.rx_err_cnt, u_stress.agent_10.stuck_seen, 1000.0/12.0);
        report("agent_11", u_stress.agent_11.max_gap, u_stress.agent_11.tx_flit_cnt,
               u_stress.agent_11.rx_vc0_cnt + u_stress.agent_11.rx_vc1_cnt,
               u_stress.agent_11.rx_err_cnt, u_stress.agent_11.stuck_seen, 1000.0/14.0);

        begin
            automatic int unsigned worst = u_stress.agent_00.max_gap;
            if (u_stress.agent_01.max_gap > worst) worst = u_stress.agent_01.max_gap;
            if (u_stress.agent_10.max_gap > worst) worst = u_stress.agent_10.max_gap;
            if (u_stress.agent_11.max_gap > worst) worst = u_stress.agent_11.max_gap;
            $display("\n  ช่องว่างยาวสุดในบรรดา agent ทั้งหมด : %0d cycle", worst);
            $display("  window ที่ใช้จำลอง                  : %0d cycle (ของจริง %0d)",
                     WINDOW, 1<<24);
            $display("  เกณฑ์เดิมที่ทำให้ false-trip บนบอร์ด : %0d cycle (2^16)", 1<<16);
        end

        $display("\n  pass_group1=%0b pass_group2=%0b any_fail=%0b", pass_g1, pass_g2, any_fail);
        //-------------------------------------------------- arbiter fairness
        begin
            automatic int unsigned e = xfer_in[EAST_P];
            automatic int unsigned n = xfer_in[NORTH_P];
            automatic int unsigned tot = e + n;
            $display("");
            $display("  flit ที่เข้า LOCAL port ของ idx0 แยกตามขาเข้า:");
            $display("    EAST  (agent_01 เดี่ยว)      : %0d", e);
            $display("    NORTH (agent_10 + agent_11) : %0d", n);
            $display("    LOCAL/SOUTH/WEST            : %0d / %0d / %0d",
                     xfer_in[LOCAL_P], xfer_in[SOUTH_P], xfer_in[WEST_P]);
            if (tot > 0)
                $display("    -> EAST %0d%%  NORTH %0d%%  (ยุติธรรม = 50/50)",
                         (e*100)/tot, (n*100)/tot);
        end

        //-------------------------------------------------- เกณฑ์ตัดสิน
        // GAP_MAX_OK ตั้งจากที่วัดได้จริง (สูงสุด 136 cycle) เผื่อไว้ ~15 เท่า
        //   ถ้า agent กลับไปตัดแพ็กเกจกลางคันอีก ตัวเลขจะพุ่งไป ~37,000 ทันที
        //   เทสต์นี้จึงเป็นตัวกันไม่ให้บั๊กนั้นกลับมาเงียบๆ
        begin
            automatic int unsigned worst = u_stress.agent_00.max_gap;
            automatic int fails = 0;
            automatic int unsigned rx0 = u_stress.agent_00.rx_vc0_cnt
                                       + u_stress.agent_00.rx_vc1_cnt;
            if (u_stress.agent_01.max_gap > worst) worst = u_stress.agent_01.max_gap;
            if (u_stress.agent_10.max_gap > worst) worst = u_stress.agent_10.max_gap;
            if (u_stress.agent_11.max_gap > worst) worst = u_stress.agent_11.max_gap;

            $display("");
            if (worst > GAP_MAX_OK) begin
                $display("  [FAIL] gap %0d cycle > limit %0d", worst, GAP_MAX_OK);
                $display("         สงสัยแพ็กเกจถูกตัดกลางคันแล้วไปล็อก packet_arbiter ค้าง");
                fails++;
            end else
                $display("  [PASS] gap %0d cycle <= limit %0d", worst, GAP_MAX_OK);

            if (u_stress.agent_00.rx_err_cnt != 0) begin
                $display("  [FAIL] sequence errors = %0d", u_stress.agent_00.rx_err_cnt);
                fails++;
            end else
                $display("  [PASS] no sequence errors");

            if (rx0 == 0) begin
                $display("  [FAIL] sink received nothing");
                fails++;
            end else
                $display("  [PASS] sink received %0d flits", rx0);

            // round-robin ที่ LOCAL port ของ idx0 ต้องแบ่งขาเข้าสองขาราวครึ่งต่อครึ่ง
            // เผื่อ +-5% กันความแปรปรวนของ GALS (แต่ละขามาคนละโดเมนนาฬิกา)
            begin
                automatic int unsigned e = xfer_in[EAST_P];
                automatic int unsigned n = xfer_in[NORTH_P];
                automatic int unsigned tot = e + n;
                automatic int unsigned ep = (tot > 0) ? (e*100)/tot : 0;
                if (tot == 0) begin
                    $display("  [FAIL] ไม่มี flit ผ่าน LOCAL port ของ idx0 เลย");
                    fails++;
                end else if (ep < 45 || ep > 55) begin
                    $display("  [FAIL] arbiter ไม่ยุติธรรม: EAST %0d%% / NORTH %0d%%", ep, 100-ep);
                    fails++;
                end else
                    $display("  [PASS] arbiter แบ่งขาเข้า EAST %0d%% / NORTH %0d%%", ep, 100-ep);
            end

            $display("");
            if (fails == 0) $display("  >>> tb_noc_stress_tester PASS");
            else            $display("  >>> tb_noc_stress_tester FAIL (%0d)", fails);
        end
        $display("=================================================\n");
        $finish;
    end

endmodule
