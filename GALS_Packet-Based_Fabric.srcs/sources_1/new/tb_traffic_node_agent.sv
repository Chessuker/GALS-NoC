`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: tb_traffic_node_agent
//
// พิสูจน์ liveness watchdog ใน traffic_node_agent
//
// ที่มา (HANDOFF.md gotcha 2): state machine ของ agent เดินตาม win_cnt อย่างเดียว
//   มันจึงไปถึง S_DONE แล้วชู done ได้ ต่อให้ fabric ตายสนิท
//   รัน VC_MODE=2 ก่อนแก้ bug #3 ไฟเขียวติดบน fabric ที่ deadlock มาแล้วจริงๆ
//   -> done ต้องอาศัยหลักฐานว่ามี flit ขยับ ไม่ใช่แค่ "นับครบ"
//
// หมายเหตุ: traffic_node_agent ไม่เคยถูกจำลองเลยแม้แต่ครั้งเดียว
//   tb_noc_mesh_2x2_gals ใช้ traffic_gen คนละตัวกัน
//   ไฟล์นี้จึงเป็นเทสต์เบนช์ตัวแรกของโมดูลนี้
//
// รันเดี่ยวๆ ได้เลย ไม่ต้องพึ่ง NoC:
//   xvlog -sv traffic_node_agent.sv tb_traffic_node_agent.sv
//   xelab -s tb work.tb_traffic_node_agent && xsim tb -R
//////////////////////////////////////////////////////////////////////////////////

module tb_traffic_node_agent;

    // ย่อ window ทั้งหมดลงให้รันจบไว ๆ แต่คงสัดส่วนเดิมไว้
    //   WINDOW (2^12) ยาวกว่า STUCK (2^6) 64 เท่า
    //   ของจริงคือ 2^24 / 2^16 = 256 เท่า
    localparam int WARMUP_LOG = 4;
    localparam int WINDOW_LOG = 12;
    localparam int DRAIN_LOG  = 4;
    localparam int STUCK_LOG  = 6;      // 64 cycle เงียบสนิท = ตาย
    localparam int STUCK_CYC  = 1 << STUCK_LOG;

    logic clk = 1'b0;
    logic rst_n;
    always #5 clk = ~clk;               // 100 MHz

    int pass_cnt = 0, fail_cnt = 0;

    task automatic check(input string name, input logic got, input logic exp);
        // label เป็น ASCII ล้วน: xsim ทำ UTF-8 ที่ส่งผ่าน string argument พัง
        // (ข้อความไทยที่เป็น literal ใน $display ตรงๆ ไม่มีปัญหา)
        if (got === exp) begin
            pass_cnt++;
            $display("  [PASS] %s | done=%0b", name, got);
        end else begin
            fail_cnt++;
            $display("  [FAIL] %s | done=%0b (คาดว่า %0b)", name, got, exp);
        end
    endtask

    //=====================================================================
    // DUT 1 : sender (TX_EN=1) — พิสูจน์ liveness ด้วย tx_fire
    //=====================================================================
    logic [1:0] s_tready;
    logic       s_txvalid;
    logic [1:0] s_txtid;
    logic       s_done, s_err;

    traffic_node_agent #(
        .DEST_ID(4'b0000), .SRC_TAG(2'b01), .PKT_FLITS(16), .VC_MODE(2),
        .WINDOW_LOG(WINDOW_LOG), .WARMUP_LOG(WARMUP_LOG), .DRAIN_LOG(DRAIN_LOG),
        .STUCK_LOG(STUCK_LOG), .TX_EN(1'b1)
    ) dut_tx (
        .clk(clk), .rst_n(rst_n),
        .rx_tdata('0), .rx_tdest('0), .rx_tid('0), .rx_tlast(1'b0), .rx_tvalid(1'b0),
        .rx_tready(),
        .tx_tdata(), .tx_tdest(), .tx_tid(s_txtid), .tx_tlast(),
        .tx_tvalid(s_txvalid), .tx_tready(s_tready),
        .done(s_done), .err(s_err)
    );

    //=====================================================================
    // DUT 2 : sink (TX_EN=0) — ไม่เคยส่ง จึงพิสูจน์ด้วย rx_fire
    //   ตัวนี้สำคัญ: ถ้า watchdog ไปจับ tx_fire กับ sink มันจะ false-fail ทุกครั้ง
    //=====================================================================
    logic       k_rxvalid;
    logic [7:0] k_rxdata;
    logic       k_done, k_err;

    traffic_node_agent #(
        .DEST_ID(4'b0000), .SRC_TAG(2'b00), .PKT_FLITS(16), .VC_MODE(2),
        .WINDOW_LOG(WINDOW_LOG), .WARMUP_LOG(WARMUP_LOG), .DRAIN_LOG(DRAIN_LOG),
        .STUCK_LOG(STUCK_LOG), .TX_EN(1'b0)
    ) dut_rx (
        .clk(clk), .rst_n(rst_n),
        .rx_tdata(k_rxdata), .rx_tdest(4'b0000), .rx_tid(2'b01), .rx_tlast(1'b0),
        .rx_tvalid(k_rxvalid), .rx_tready(),
        .tx_tdata(), .tx_tdest(), .tx_tid(), .tx_tlast(), .tx_tvalid(),
        .tx_tready(2'b11),
        .done(k_done), .err(k_err)
    );

    // ป้อน sequence ที่ถูกต้องให้ sink จะได้ไม่ไปติด err (เราสนใจแค่ done)
    logic [5:0] k_seq = '0;
    assign k_rxdata = {2'b01, k_seq};
    always_ff @(posedge clk) if (k_rxvalid) k_seq <= k_seq + 1'b1;

    // รอจน agent ทั้งสองตัวพ้น S_DONE (เผื่อเวลาไว้เหลือเฟือ)
    //   +PKT_FLITS*STUCK_CYC : agent ไม่ออกจาก S_RUN กลางแพ็กเกจอีกแล้ว
    //   หน้าต่างนับครบแล้วมันยังส่งต่อจนจบแพ็กเกจ ซึ่งตอน backpressure หนัก
    //   (เคส 5) กินได้ถึง 16 flit x 64 cycle ถ้าไม่เผื่อไว้ เช็คจะไปอ่านตอนยังไม่จบ
    localparam int PKT_FLITS = 16;
    localparam int RUN_NS = 10 * ((1<<WARMUP_LOG) + (1<<WINDOW_LOG) + (1<<DRAIN_LOG)
                                  + PKT_FLITS*STUCK_CYC + 500);

    //=====================================================================
    initial begin
        $display("\n=================================================");
        $display(" tb_traffic_node_agent : liveness watchdog");
        $display(" WINDOW=2^%0d  STUCK=2^%0d (%0d cycle)", WINDOW_LOG, STUCK_LOG, STUCK_CYC);
        $display("=================================================\n");

        //-------------------------------------------------- 1. sender ปกติ
        $display("[1] sender, fabric รับตลอด  -> ต้องผ่าน");
        rst_n = 0; s_tready = 2'b11; k_rxvalid = 1'b1;
        #100 rst_n = 1;
        #RUN_NS;
        check("healthy sender      -> done must assert", s_done, 1'b1);
        check("healthy sink        -> done must assert", k_done, 1'b1);

        //-------------------------------------------------- 2. fabric ตายสนิท
        $display("\n[2] fabric ไม่รับเลยทั้ง window (deadlock) -> ต้องไม่ผ่าน");
        rst_n = 0; s_tready = 2'b00; k_rxvalid = 1'b0;
        #100 rst_n = 1;
        #RUN_NS;
        check("dead sender         -> done must stay low", s_done, 1'b0);
        check("dead sink           -> done must stay low", k_done, 1'b0);

        //-------------------------------------------------- 3. ตายกลางคัน
        // เดินปกติสักพักแล้วค่อยตาย — เคสจริงของ bug #3 คือแบบนี้
        $display("\n[3] เดินปกติแล้วตายกลางคัน -> ต้องไม่ผ่าน (ธงต้องค้าง)");
        rst_n = 0; s_tready = 2'b11; k_rxvalid = 1'b1;
        #100 rst_n = 1;
        #(RUN_NS/4);
        s_tready = 2'b00; k_rxvalid = 1'b0;      // ตาย
        #RUN_NS;
        check("sender dies midway  -> done must stay low", s_done, 1'b0);
        check("sink dies midway    -> done must stay low", k_done, 1'b0);

        //-------------------------------------------------- 4. ตายแล้วฟื้น
        // ธง stuck_seen ต้องค้าง ไม่ใช่หายไปเพราะกลับมาวิ่งได้ตอนท้าย
        $display("\n[4] ตายครบรอบแล้วฟื้น -> ยังต้องไม่ผ่าน (ห้ามล้างธง)");
        rst_n = 0; s_tready = 2'b11; k_rxvalid = 1'b1;
        #100 rst_n = 1;
        #(RUN_NS/4);
        s_tready = 2'b00; k_rxvalid = 1'b0;
        #(10 * STUCK_CYC * 3);                   // เงียบยาวกว่า STUCK ชัดๆ
        s_tready = 2'b11; k_rxvalid = 1'b1;      // ฟื้น
        #RUN_NS;
        check("sender revives      -> flag must stick", s_done, 1'b0);
        check("sink revives        -> flag must stick", k_done, 1'b0);

        //-------------------------------------------------- 5. กันแตกตื่น
        // backpressure หนักแต่ยังเดิน ช่องว่างสั้นกว่า STUCK -> ห้าม false trip
        // เคสนี้สำคัญที่สุด: ถ้า watchdog ตั้งแน่นไป ของดีจะถูกตีตกทุกครั้ง
        $display("\n[5] backpressure หนัก ช่องว่างสั้นกว่า STUCK -> ต้องผ่าน (ห้าม false trip)");
        rst_n = 0; s_tready = 2'b00; k_rxvalid = 1'b0;
        #100 rst_n = 1;
        fork
            begin
                forever begin
                    // ปล่อยผ่าน 1 จังหวะ แล้วบล็อกยาวเกือบเท่า STUCK
                    @(posedge clk); s_tready = 2'b11; k_rxvalid = 1'b1;
                    @(posedge clk); s_tready = 2'b00; k_rxvalid = 1'b0;
                    repeat (STUCK_CYC - 4) @(posedge clk);
                end
            end
            #RUN_NS;
        join_any
        disable fork;
        check("heavy stall, alive  -> sender must pass", s_done, 1'b1);
        check("heavy stall, alive  -> sink must pass", k_done, 1'b1);

        //--------------------------------------------------
        $display("\n=================================================");
        $display(" ผลรวม: PASS=%0d  FAIL=%0d", pass_cnt, fail_cnt);
        if (fail_cnt == 0) $display(" >>> liveness watchdog ผ่านทุกเคส");
        else               $display(" >>> มีเคสไม่ผ่าน");
        $display("=================================================\n");
        $finish;
    end

endmodule
