`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: tb_ecc_secded
//
// พิสูจน์ ECC SECDED (13,8) แบบ exhaustive + ทดสอบ dual_port_ram_ecc ทั้งเส้นทาง
//
// ที่มา: ecc_secded_encode_8b / ecc_secded_decode_8b / dual_port_ram_ecc
//   ไม่เคยถูกทดสอบเลยแม้แต่ครั้งเดียว ทั้งที่มันอยู่บน datapath ของ *ทุก flit*
//   ที่ข้ามขอบ GALS (async_fifo -> dual_port_ram_ecc) ในทุก build
//   ที่แย่กว่านั้น: ecc_single_err / ecc_double_err ถูกต่อขึ้นมาถึง
//   gals_node_wrapper แล้วปล่อยลอย ( .ecc_double_err() ) — double-bit error
//   จึงถูกส่งต่อเป็นข้อมูลเสียเงียบๆ ไม่มีใครรู้
//
// ตรรกะ ECC เป็น combinational ล้วนและเล็ก จึงทดสอบ *ครบทุกกรณี* ได้
// ไม่ต้องสุ่ม:
//   1. ไม่มี error         : 256 ค่า
//   2. พัง 1 บิต           : 256 x 13 ตำแหน่ง = 3,328 กรณี
//   3. พัง 2 บิต           : 256 x C(13,2)=78 = 19,968 กรณี
//   4. ผ่าน RAM จริง       : encode -> เขียน -> พลิกบิตใน mem -> อ่าน -> decode
//
// รันเดี่ยวๆ:
//   xvlog -sv ecc_secded_encode_8b.sv ecc_secded_decode_8b.sv \
//             dual_port_ram.sv dual_port_ram_ecc.sv tb_ecc_secded.sv
//   xelab -s tb work.tb_ecc_secded && xsim tb -R
//////////////////////////////////////////////////////////////////////////////////

module tb_ecc_secded;

    localparam int DW = 8;    // data bits
    localparam int TW = 13;   // encoded bits (8 data + 4 hamming + 1 overall parity)

    int pass_cnt = 0, fail_cnt = 0;
    int first_fail_shown = 0;

    // แสดงรายละเอียดเฉพาะ 10 ความผิดพลาดแรก ไม่งั้น log จะท่วม
    task automatic fail(string what, input int a, input int b, input int c);
        fail_cnt++;
        if (first_fail_shown < 10) begin
            first_fail_shown++;
            $display("  [FAIL] %s : data=0x%02h arg1=%0d arg2=%0d", what, a, b, c);
        end
    endtask

    //=====================================================================
    // DUT 1/2 : encoder + decoder ต่อตรง (ฉีด error คั่นกลาง)
    //=====================================================================
    logic [DW-1:0]  enc_data;
    logic [TW-1:0]  enc_word;
    logic [TW-1:0]  corrupted;
    logic [DW-1:0]  dec_data;
    logic           dec_single, dec_double;

    ecc_secded_encode_8b u_enc (.data_in(enc_data), .encoded_out(enc_word));
    ecc_secded_decode_8b u_dec (.encoded_in(corrupted), .data_out(dec_data),
                                .single_err(dec_single), .double_err(dec_double));

    //=====================================================================
    // DUT 3 : ทั้งก้อน dual_port_ram_ecc (พิสูจน์ว่าสายต่อถูกด้วย
    //         ไม่ใช่แค่ตรรกะ encode/decode ถูก)
    //=====================================================================
    localparam int AW = 4;
    logic           clk = 0;
    logic           w_en, r_en;
    logic [AW-1:0]  waddr, raddr;
    logic [DW-1:0]  ram_wdata, ram_rdata;
    logic           ram_single, ram_double;

    always #5 clk = ~clk;

    dual_port_ram_ecc #(.DATA_WIDTH(DW), .ADDR_WIDTH(AW)) u_ram (
        .wclk(clk), .w_en(w_en), .waddr(waddr), .wdata(ram_wdata),
        .rclk(clk), .r_en(r_en), .raddr(raddr), .rdata(ram_rdata),
        .ecc_single_err(ram_single), .ecc_double_err(ram_double)
    );

    // เขียน 1 คำลง RAM
    task automatic ram_write(input logic [AW-1:0] a, input logic [DW-1:0] d);
        @(negedge clk);
        waddr = a; ram_wdata = d; w_en = 1'b1;
        @(negedge clk);
        w_en = 1'b0;
    endtask

    // อ่าน 1 คำจาก RAM
    task automatic ram_read(input logic [AW-1:0] a);
        @(negedge clk);
        raddr = a; r_en = 1'b1;
        @(negedge clk);
        r_en = 1'b0;
        #1;   // ให้ decoder (combinational) นิ่งก่อนอ่านผล
    endtask

    // พลิกบิตในเนื้อ RAM โดยตรง = จำลอง SEU/บิตเน่าในหน่วยความจำ
    // เป็นเหตุผลเดียวที่ ECC มีอยู่ ถ้าไม่ฉีดตรงนี้ก็ไม่ได้ทดสอบอะไรเลย
    task automatic ram_flip(input logic [AW-1:0] a, input int bit_idx);
        u_ram.core_ram.mem[a][bit_idx] = ~u_ram.core_ram.mem[a][bit_idx];
    endtask

    //=====================================================================
    initial begin
        automatic int n_clean = 0, n_sbe = 0, n_dbe = 0, n_ram = 0;

        $display("\n=================================================");
        $display(" tb_ecc_secded : exhaustive SECDED (%0d,%0d)", TW, DW);
        $display("=================================================\n");

        w_en = 0; r_en = 0; waddr = 0; raddr = 0; ram_wdata = 0;

        //-------------------------------------------------- 1. ไม่มี error
        $display("[1] ไม่มี error : ทุกค่า 0x00-0xFF ต้องถอดกลับได้เป๊ะ ไม่มีธงขึ้น");
        for (int d = 0; d < 256; d++) begin
            enc_data = d[DW-1:0]; #1;
            corrupted = enc_word; #1;
            n_clean++;
            if (dec_data !== d[DW-1:0]) fail("clean: data ผิด", d, dec_data, 0);
            else if (dec_single || dec_double) fail("clean: ธงขึ้นทั้งที่ไม่มี error", d, dec_single, dec_double);
            else pass_cnt++;
        end
        $display("    ตรวจ %0d กรณี", n_clean);

        //-------------------------------------------------- 2. พัง 1 บิต
        // ต้อง: single_err=1, double_err=0, และซ่อมข้อมูลกลับมาถูกต้อง
        // รวมถึงกรณีพังที่ตัวบิต overall parity เอง (bit 12) ซึ่งข้อมูลไม่เสีย
        $display("[2] พัง 1 บิต : ต้องตรวจเจอ ซ่อมได้ และข้อมูลต้องถูกต้อง");
        for (int d = 0; d < 256; d++) begin
            enc_data = d[DW-1:0]; #1;
            for (int b = 0; b < TW; b++) begin
                corrupted = enc_word ^ (1 << b); #1;
                n_sbe++;
                if (!dec_single)      fail("sbe: ไม่ยกธง single", d, b, 0);
                else if (dec_double)  fail("sbe: ยกธง double ผิด", d, b, 0);
                else if (dec_data !== d[DW-1:0]) fail("sbe: ซ่อมไม่สำเร็จ", d, b, dec_data);
                else pass_cnt++;
            end
        end
        $display("    ตรวจ %0d กรณี (256 x %0d ตำแหน่ง)", n_sbe, TW);

        //-------------------------------------------------- 3. พัง 2 บิต
        // ต้อง: double_err=1 (ตรวจเจอว่าซ่อมไม่ได้) และ single_err=0
        // ข้อมูลที่ออกมาจะผิดก็ได้ — SECDED รับประกันแค่ "ตรวจเจอ" ไม่ใช่ "ซ่อมได้"
        $display("[3] พัง 2 บิต : ต้องตรวจเจอว่าซ่อมไม่ได้ (ไม่รับประกันว่าข้อมูลถูก)");
        for (int d = 0; d < 256; d++) begin
            enc_data = d[DW-1:0]; #1;
            for (int b1 = 0; b1 < TW; b1++) begin
                for (int b2 = b1+1; b2 < TW; b2++) begin
                    corrupted = enc_word ^ (1 << b1) ^ (1 << b2); #1;
                    n_dbe++;
                    if (!dec_double)     fail("dbe: ไม่ยกธง double", d, b1, b2);
                    else if (dec_single) fail("dbe: ยกธง single ผิด", d, b1, b2);
                    else pass_cnt++;
                end
            end
        end
        $display("    ตรวจ %0d กรณี (256 x C(%0d,2))", n_dbe, TW);

        //-------------------------------------------------- 4. ผ่าน RAM จริง
        // ข้อ 1-3 พิสูจน์ตรรกะ ข้อนี้พิสูจน์ว่า encoder -> RAM -> decoder ต่อสายถูก
        // ถ้าสลับบิตหรือต่อผิด ข้อ 1-3 จะยังผ่านหมดแต่ของจริงพัง
        $display("[4] ผ่าน dual_port_ram_ecc จริง : เขียน -> พลิกบิตใน mem -> อ่าน");
        for (int d = 0; d < 16; d++) begin
            automatic logic [AW-1:0] a = d[AW-1:0];
            automatic logic [DW-1:0] dv = {d[3:0], ~d[3:0]};

            // 4a. เขียนแล้วอ่านเฉยๆ ต้องได้ของเดิม ไม่มีธง
            ram_write(a, dv);
            ram_read(a);
            n_ram++;
            if (ram_rdata !== dv)              fail("ram clean: data ผิด", dv, ram_rdata, 0);
            else if (ram_single || ram_double) fail("ram clean: ธงขึ้นเอง", dv, ram_single, ram_double);
            else pass_cnt++;

            // 4b. พลิก 1 บิตใน RAM -> ต้องซ่อมได้ และยกธง single
            for (int b = 0; b < TW; b++) begin
                ram_write(a, dv);
                ram_flip(a, b);
                ram_read(a);
                n_ram++;
                if (!ram_single)          fail("ram sbe: ไม่ยกธง", dv, b, 0);
                else if (ram_double)      fail("ram sbe: ยกธง double ผิด", dv, b, 0);
                else if (ram_rdata !== dv) fail("ram sbe: ซ่อมไม่สำเร็จ", dv, b, ram_rdata);
                else pass_cnt++;
            end

            // 4c. พลิก 2 บิตใน RAM -> ต้องยกธง double
            ram_write(a, dv);
            ram_flip(a, 0);
            ram_flip(a, 5);
            ram_read(a);
            n_ram++;
            if (!ram_double)         fail("ram dbe: ไม่ยกธง double", dv, 0, 5);
            else if (ram_single)     fail("ram dbe: ยกธง single ผิด", dv, 0, 5);
            else pass_cnt++;
        end
        $display("    ตรวจ %0d กรณี", n_ram);

        //--------------------------------------------------
        $display("");
        $display("=================================================");
        $display(" ผลรวม: PASS=%0d  FAIL=%0d  (รวม %0d กรณี)",
                 pass_cnt, fail_cnt, n_clean + n_sbe + n_dbe + n_ram);
        if (fail_cnt == 0)
            $display(" >>> tb_ecc_secded PASS - SECDED ครบทุกกรณีที่รับประกัน");
        else
            $display(" >>> tb_ecc_secded FAIL");
        $display("=================================================");
        $display("");
        $display(" หมายเหตุขอบเขต: SECDED รับประกันแค่ ซ่อม 1 บิต / ตรวจเจอ 2 บิต");
        $display("   พัง 3 บิตขึ้นไปอยู่นอกการรับประกัน อาจถูกรายงานเป็น single");
        $display("   แล้ว 'ซ่อม' ผิดตัวได้ (syndrome ชี้ไปตำแหน่ง 13-15 ซึ่งไม่มีจริง)");
        $display("   ไม่ถือเป็นบั๊ก แต่ต้องรู้ไว้ตอนอ่านค่า ecc_single_err บนบอร์ด");
        $display("=================================================\n");
        $finish;
    end

endmodule
