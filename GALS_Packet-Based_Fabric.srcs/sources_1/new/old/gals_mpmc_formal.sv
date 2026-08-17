`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/17/2026 10:39:41 PM
// Design Name: 
// Module Name: gals_mpmc_formal
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


module gals_mpmc_formal #(
    parameter NUM_PRODUCERS = 4,
    parameter DATA_WIDTH = 8
)(
    input clk_C,
    input rst_C_n,
    input [NUM_PRODUCERS-1:0] clk_P,
    input [NUM_PRODUCERS-1:0] rst_P_n,
    input c_ready,
    input c_valid,
    input [$clog2(NUM_PRODUCERS)-1:0] c_source_id,
    input [NUM_PRODUCERS-1:0] fifo_empty,
    input [NUM_PRODUCERS-1:0] fifo_rd_en
);

    // =======================================================
    // 🛡️ Global Multiclock Reset Synchronizer (Formal Only)
    // =======================================================
    // ทำให้แน่ใจว่าทุกๆ โดเมนคล็อก ได้รับการ Reset อย่างสมบูรณ์ 
    // ก่อนที่ Solver จะเริ่มปล่อยให้วงจรทำงาน (ป้องกัน X-State)
    reg f_reset_done_c = 1'b0;
    always @(posedge clk_C) begin
        if (!rst_C_n) f_reset_done_c <= 1'b1;
    end

    reg [NUM_PRODUCERS-1:0] f_reset_done_p = '0;
    genvar i;
    generate
        for (i = 0; i < NUM_PRODUCERS; i++) begin : gen_rst_track
            always @(posedge clk_P[i]) begin
                if (!rst_P_n[i]) f_reset_done_p[i] <= 1'b1;
            end
        end
    endgenerate

    always @(*) begin
        // 1. บังคับให้กดปุ่ม Reset พร้อมกันทั้งระบบ
        assume(rst_P_n == {NUM_PRODUCERS{rst_C_n}});
        
        // 2. 🔴 ถือปุ่ม Reset ค้างไว้ จนกว่า "ทุกคล็อก" จะกระดิกผ่านขาขึ้นไปแล้ว 100%
        if (!f_reset_done_c || (f_reset_done_p != {NUM_PRODUCERS{1'b1}})) begin
            assume(!rst_C_n);
        end
    end

    // =======================================================
    // 🎯 Assertions & Cover Properties
    // =======================================================
    logic f_past_valid;
    initial f_past_valid = 1'b0;
    always @(posedge clk_C) f_past_valid <= 1'b1;

    always @(posedge clk_C) begin
        // 🔴 เริ่มเช็คกฎก็ต่อเมื่อมั่นใจว่าผ่านการ Reset สมบูรณ์แล้ว
        if (rst_C_n && f_past_valid && f_reset_done_c) begin
            
            assert($onehot0(fifo_rd_en));

            for (int k = 0; k < NUM_PRODUCERS; k++) begin
                if (fifo_rd_en[k]) begin
                    assert(!fifo_empty[k]);
                end
            end

            if (c_valid) begin
                assert($past(c_ready));
                assert($past(fifo_rd_en[c_source_id]));
            end

            // Cover Properties เพื่อพิสูจน์ว่าระบบเดินได้สุดทาง
            cover_end_to_end: cover(c_valid && c_ready);
            cover_p0_served:  cover(c_valid && c_source_id == 0);
            cover_pN_served:  cover(c_valid && c_source_id == NUM_PRODUCERS-1);
        end
    end
endmodule

`ifdef FORMAL
bind gals_mpmc_scalable gals_mpmc_formal #(
    .NUM_PRODUCERS(NUM_PRODUCERS),
    .DATA_WIDTH(DATA_WIDTH)
) formal_props_inst (
    .clk_C(clk_C),
    .rst_C_n(rst_C_n),
    .clk_P(clk_P),
    .rst_P_n(rst_P_n), 
    .c_ready(c_ready),
    .c_valid(c_valid),
    .c_source_id(c_source_id),
    .fifo_empty(fifo_empty),
    .fifo_rd_en(fifo_rd_en)
);
`endif
