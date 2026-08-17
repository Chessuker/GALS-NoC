`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Thawat Boonsuk
// 
// Create Date: 04/07/2026 09:02:54 PM
// Design Name: 
// Module Name: sync_2stage
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


module sync_2stage #(
    parameter WIDTH = 5  // ADDR_WIDTH + 1 ~ Gray Pointer
)(
    input logic clk,
    input logic rst,
    input logic [WIDTH-1:0] d,
    (* ASYNC_REG = "TRUE" *) output logic [WIDTH-1:0] q
    );
    
    (* ASYNC_REG = "TRUE" *) logic [WIDTH-1:0] q1;
    
    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            q1 <= '0;
            q <= '0;
        end else begin
            q1 <= d;
            q <= q1;
        end   
    end

    // =================================================================
    // FORMAL VERIFICATION BLOCK (TRUE CDC SYNCHRONIZER)
    // =================================================================
    `ifdef FORMAL
        `ifndef FORMAL_TOP_INTEGRATION

        reg f_past_valid = 1'b0;
        reg [WIDTH-1:0] f_past_q1;
        reg f_past_rst;

        always @(posedge clk) begin
            f_past_valid <= 1'b1;
            f_past_q1 <= q1;
            f_past_rst <= rst;
        end

        // 🛡️ โล่ป้องกัน Asynchronous Reset Glitch แบบเดียวกับ Gray Counter
        reg f_async_reset_hit = 1'b0;
        always @(posedge clk or posedge rst) begin
            if (rst) 
                f_async_reset_hit <= 1'b1; // จำไว้ว่ามีคนแอบมารีเซ็ตกลางอากาศ!
            else 
                f_async_reset_hit <= 1'b0;
        end

        always @(posedge clk) begin
            // 1. บังคับให้เริ่มระบบด้วยการรีเซ็ต
            if (!f_past_valid) begin
                assume(rst);
            end

            // 2. Asynchronous Reset Check
            if (rst) begin
                assert(q1 == 0);
                assert(q == 0);
            end 
            // 3. The Golden Rule of CDC
            // 🔴 เพิ่มเงื่อนไข !f_async_reset_hit เพื่อไม่ตรวจกฎถ้าระบบเพิ่งโดนแอบรีเซ็ตมา
            else if (f_past_valid && !f_past_rst && !f_async_reset_hit) begin
                assert_stage2: assert (q == f_past_q1);
            end
        end

        // 4. Reachability Cover
        always @(posedge clk) begin
            if (f_past_valid && !rst && !f_async_reset_hit) begin
                cover_data_pass: cover (q != 0);
            end
        end
        `endif
    `endif

endmodule
