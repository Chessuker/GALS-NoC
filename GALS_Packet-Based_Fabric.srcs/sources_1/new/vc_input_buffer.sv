`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/03/2026 10:32:33 PM
// Design Name: 
// Module Name: vc_input_buffer
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


module vc_input_buffer #(
    parameter DATA_W = 8,
    parameter CORD_W = 2,
    parameter NUM_VCS = 2,    // จำนวน Virtual Channels (เช่น 2 เลน)
    parameter DEPTH = 16      // ความลึกของ FIFO แต่ละ VC
)(
    input  logic clk,
    input  logic rst_n,

    // ---------------------------------------------------------
    // ฝั่งรับเข้า (RX from Network/Host) - สายไฟเส้นเดียว
    // ---------------------------------------------------------
    input  logic              s_valid,
    input  logic              s_tlast,
    input  logic [3:0]        s_tdest,
    input  logic [DATA_W-1:0] s_tdata,
    input  logic [NUM_VCS-1:0]s_tid,   // VC ID แบบ One-hot (01 = VC0, 10 = VC1)
    output logic [NUM_VCS-1:0]s_ready, // แจ้งกลับไปว่า VC ไหนพร้อมรับบ้าง (Per-VC Backpressure)

    // ---------------------------------------------------------
    // ฝั่งส่งออก (TX to Router Switch) - แยกสายไฟตามจำนวน VC
    // ---------------------------------------------------------
    output logic              m_valid [NUM_VCS],
    output logic              m_tlast [NUM_VCS],
    output logic [3:0]        m_tdest [NUM_VCS],
    output logic [DATA_W-1:0] m_tdata [NUM_VCS],
    input  logic              m_ready [NUM_VCS]
);

    // สร้าง FIFO แยกสำหรับแต่ละ Virtual Channel
    generate
        for (genvar v = 0; v < NUM_VCS; v++) begin : gen_vc_fifo
            
            // สัญญาณ write enable สำหรับ FIFO ตัวนี้ (เมื่อ Valid มา และ TID ชี้มาที่ VC นี้)
            logic fifo_we;
            assign fifo_we = s_valid && s_tid[v];

            // ข้อมูลที่รวมกันเป็นก้อนเดียวเพื่อเก็บลง FIFO (TLAST + TDEST + TDATA)
            localparam PACK_W = 1 + 4 + DATA_W;
            logic [PACK_W-1:0] wdata, rdata;
            
            assign wdata = {s_tlast, s_tdest, s_tdata};
            
            logic fifo_full, fifo_empty;
            
            // แจ้งสถานะ Ready ของ VC นี้กลับไปให้ผู้ส่ง
            assign s_ready[v] = ~fifo_full;

            // Instantiate Synchronous FIFO สำหรับเลนนี้
            sync_fifo #(
                .DATA_WIDTH(PACK_W),
                .DEPTH(DEPTH)
            ) vc_fifo_inst (
                .clk(clk),
                .rst_n(rst_n),
                .w_en(fifo_we && !fifo_full),
                .w_data(wdata),
                .r_en(m_ready[v] && !fifo_empty),
                .r_data(rdata),
                .full(fifo_full),
                .empty(fifo_empty)
            );

            // กระจายข้อมูลที่อ่านได้ออกจาก FIFO
            assign m_valid[v] = ~fifo_empty;
            assign m_tlast[v] = rdata[PACK_W-1];
            assign m_tdest[v] = rdata[DATA_W+3 : DATA_W];
            assign m_tdata[v] = rdata[DATA_W-1 : 0];

        end
    endgenerate


    // =================================================================
    // FORMAL
    //
    // โมดูลนี้ไม่เคยถูกพิสูจน์เลย ทั้งที่ทุก flit ที่เข้า router ต้องผ่านมันก่อน
    // งานของมันมีสามอย่าง และพังได้ทั้งสามอย่างแบบเงียบๆ:
    //   1. demux ตาม s_tid  — ยัดผิดเลน แพกเกจไปโผล่ VC อื่น
    //   2. pack/unpack {tlast,tdest,tdata} — สไลซ์บิตเพี้ยน จ่าหน้าซองเปลี่ยน
    //   3. per-VC backpressure — s_ready ผิดแล้ว flit หายเงียบ
    //      (w_en ถูก and ด้วย !fifo_full ไว้แล้ว การ "ดรอป" จึงไม่มีใครแจ้ง)
    //
    // วิธีพิสูจน์: shadow FIFO แบบ black-box ล้วน — เก็บของที่ *ควรจะได้* ไว้เอง
    // ด้วยตัวนับของตัวเอง ไม่แตะภายใน sync_fifo แม้แต่บิตเดียว แล้วเทียบกับหัวคิว
    // ที่โมดูลคายออกมาจริง ผ่านทั้งสามข้อพร้อมกัน: ลำดับถูก ข้อมูลครบ ไม่หาย
    // ไม่ซ้ำ ไม่ข้ามเลน
    //
    // ข้อจำกัดที่ต้องรู้: การเทียบเนื้อ shadow กับเนื้อ FIFO *ไม่เป็น inductive*
    // โดยธรรมชาติ — induction เริ่มจากสถานะที่ shadow กับ mem ไม่ตรงกันได้เลย
    // จะให้เป็น unbounded ต้องอ้าง mem ภายใน FIFO เข้ามาผูกเป็น invariant
    // ซึ่งทำให้ property กลายเป็น white-box สคริปต์จึงรัน bmc (bounded)
    // ต่างจากอีกเจ็ดโมดูลที่เป็น prove ดู vc_input_buffer.sby
    // =================================================================
    `ifdef FORMAL
    `ifndef FORMAL_TOP_INTEGRATION
        // sync_fifo ไม่มีค่า init ให้พอยน์เตอร์ solver จึงเริ่มจากคิวที่มีของค้าง
        // อยู่แล้วโดยไม่เคยมีใครเขียนลงไป — บังคับให้ผ่านรีเซ็ตก่อนหนึ่งไซเคิล
        // (rst_n เป็น async ค่าจึงถูกล้างทันทีในไซเคิลนั้น)
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

        localparam int F_PACK_W = 1 + 4 + DATA_W;
        localparam int F_ADDR_W = $clog2(DEPTH);
        localparam int F_CNT_W  = $clog2(DEPTH + 1);

        reg f_past_valid = 1'b0;
        always @(posedge clk) f_past_valid <= 1'b1;

        // -------------------------------------------------------------
        // สมมติฐานฝั่งต้นทาง
        // -------------------------------------------------------------
        always @(*) begin
            if (s_valid) begin
                // s_tid ประกาศไว้ว่าเป็น one-hot แต่ RTL ไม่ได้บังคับอะไรเลย
                // ถ้า multi-hot จริง flit เดียวจะถูกแจกลงหลาย VC พร้อมกัน
                // และ s_ready แยกต่อ VC — บาง VC รับ บาง VC ดรอป แพกเกจขาดกลาง
                assume(f_onehot(s_tid));
                // ต้นทางต้องเคารพ backpressure ต่อ VC (สัญญา AXI4-Stream)
                // ถ้าไม่ assume ข้อนี้ flit จะหายจริงตาม w_en = fifo_we && !fifo_full
                assume((s_tid & ~s_ready) == '0);
            end
        end

        generate
            for (genvar v = 0; v < NUM_VCS; v++) begin : gen_f_vc

                // flit ที่ถูกรับ/ถูกดึงออกจริงในเลนนี้
                wire f_wr = s_valid   && s_tid[v] && s_ready[v];
                wire f_rd = m_ready[v] && m_valid[v];

                // shadow: คิวเงาที่เก็บของที่ควรจะได้ พร้อมพอยน์เตอร์ของตัวเอง
                logic              sh_tlast [DEPTH];
                logic [3:0]        sh_tdest [DEPTH];
                logic [DATA_W-1:0] sh_tdata [DEPTH];

                logic [F_ADDR_W-1:0] f_wp, f_rp;
                logic [F_CNT_W-1:0]  f_cnt;

                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        f_wp  <= '0;
                        f_rp  <= '0;
                        f_cnt <= '0;
                    end else begin
                        if (f_wr) begin
                            sh_tlast[f_wp] <= s_tlast;
                            sh_tdest[f_wp] <= s_tdest;
                            sh_tdata[f_wp] <= s_tdata;
                            f_wp <= f_wp + 1'b1;
                        end
                        if (f_rd) f_rp <= f_rp + 1'b1;

                        if (f_wr && !f_rd)      f_cnt <= f_cnt + 1'b1;
                        else if (f_rd && !f_wr) f_cnt <= f_cnt - 1'b1;
                    end
                end

                always @(*) begin
                    if (rst_n && f_past_valid) begin
                        // ตีกรอบให้ solver ไม่มโนคิวล้น
                        assert_inv_cnt_cap: assert(f_cnt <= DEPTH);

                        // ธงว่าง/เต็มต้องตรงกับจำนวนของที่ค้างอยู่จริง
                        // ผิดข้อนี้ = flit หาย (ready ค้าง 1 ตอนเต็ม)
                        //          หรือ flit ผี (valid ค้าง 1 ตอนว่าง)
                        assert_valid_iff_occupied: assert(m_valid[v] == (f_cnt != 0));
                        assert_ready_iff_room:     assert(s_ready[v] == (f_cnt != DEPTH));

                        // หัวใจ: หัวคิวที่คายออกมาต้องเป็นของชิ้นที่เขียนเข้าไป
                        // ตำแหน่งนั้นเป๊ะ ครอบทั้ง demux, pack/unpack และลำดับ FIFO
                        if (f_cnt != 0) begin
                            assert_head_tlast: assert(m_tlast[v] == sh_tlast[f_rp]);
                            assert_head_tdest: assert(m_tdest[v] == sh_tdest[f_rp]);
                            assert_head_tdata: assert(m_tdata[v] == sh_tdata[f_rp]);
                        end
                    end
                end

                always @(posedge clk) begin
                    if (f_past_valid && $past(rst_n) && rst_n) begin
                        // เลนอื่นห้ามขยับเพราะ flit ที่ไม่ได้จ่าหน้ามาที่ตัวเอง
                        if (!$past(s_tid[v]) || !$past(s_valid)) begin
                            assert_no_cross_vc_write: assert(f_wp == $past(f_wp));
                        end

                        // COVER: ของจริงต้องไหลได้ ไม่ใช่ผ่านเพราะไม่มีอะไรเกิดขึ้น
                        cover_flit_through: cover($past(f_wr) && f_rd);
                        cover_fifo_full:    cover(f_cnt == DEPTH);
                        cover_eop_out:      cover(f_rd && m_tlast[v]);
                    end
                end
            end
        endgenerate

        // COVER: สองเลนมีของค้างพร้อมกัน = per-VC buffering ทำงานจริง
        // (ถ้าเลนเดียวเต็มแล้วอีกเลนตายด้วย ก็ไม่ใช่ VC)
        always @(posedge clk) begin
            if (f_past_valid && rst_n && NUM_VCS == 2) begin
                cover_both_vcs_busy: cover(m_valid[0] && m_valid[1]);
                cover_vc0_full_vc1_open:
                    cover(!s_ready[0] && s_ready[1] && m_valid[1]);
            end
        end
    `endif
    `endif

endmodule

