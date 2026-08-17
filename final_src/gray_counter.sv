`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Thawat Boonsuk
// 
// Create Date: 04/07/2026 08:27:10 PM
// Design Name: 
// Module Name: gray_counter
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


module gray_counter #(
    parameter ADDR_WIDTH = 4
)(
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  en,
    output logic [ADDR_WIDTH:0]   ptr_g,
    output logic [ADDR_WIDTH-1:0] addr
);
    
    // =================================================================
    // ลอจิกฮาร์ดแวร์หลัก (RTL)
    // =================================================================
    logic [ADDR_WIDTH:0] bin;
    logic [ADDR_WIDTH:0] bin_next;
    logic [ADDR_WIDTH:0] gray_next;
    
    assign bin_next = bin + en;
    assign gray_next = bin_next ^ (bin_next >> 1);
    assign addr = bin[ADDR_WIDTH-1:0];
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bin <= 0;
            ptr_g <= 0;
        end else begin
            bin <= bin_next;
            ptr_g <= gray_next;
        end
    end

    // =================================================================
    // FORMAL VERIFICATION BLOCK (Yosys-Safe Style)
    // =================================================================
    `ifdef FORMAL
        `ifndef FORMAL_TOP_INTEGRATION
        // -------------------------------------------------------------
        // 1. Manual Past Tracking (แก้บั๊ก Multiclock ของ Yosys)
        // -------------------------------------------------------------
        reg f_past_valid = 1'b0;
        reg f_past_en;
        reg [ADDR_WIDTH:0] f_past_bin;
        reg [ADDR_WIDTH:0] f_past_ptr_g;
        reg f_past_rst;

        // เราก๊อปปี้ค่าเก็บไว้ในทุกๆ ขอบคล็อกด้วยตัวเอง (ปลอดภัย 100%)
        always @(posedge clk) begin
            f_past_valid <= 1'b1;
            f_past_en <= en;
            f_past_bin <= bin;
            f_past_ptr_g <= ptr_g;
            f_past_rst <= rst;
        end

        // -------------------------------------------------------------
        // 2. Async Reset Glitch Detector (โล่ป้องกันการโจมตีกลางอากาศ)
        // -------------------------------------------------------------
        reg f_async_reset_hit = 1'b0;
        always @(posedge clk or posedge rst) begin
            if (rst) 
                f_async_reset_hit <= 1'b1; // ถ้ามีสาย Reset กระตุกแม้แต่นิดเดียว ให้จำไว้!
            else 
                f_async_reset_hit <= 1'b0;
        end

        // -------------------------------------------------------------
        // 3. Procedural Assertions (เขียนแบบดื้อๆ Yosys ชอบมาก)
        // -------------------------------------------------------------
        always @(posedge clk) begin
            // บังคับให้เริ่มระบบด้วยการกด Reset เสมอ
            if (!f_past_valid) begin
                assume(rst);
            end
            
            // ตรวจสอบค่าตอนรีเซ็ต
            if (rst) begin
                assert(bin == 0);
                assert(ptr_g == 0);
            end else begin
                // สมการ Binary -> Gray ต้องถูกเสมอ
                assert(ptr_g == (bin ^ (bin >> 1)));
            end

            // ตรวจสอบการเคลื่อนที่: "ห้ามมีรอยด่างพร้อยจากการรีเซ็ตมาเกี่ยวข้องเด็ดขาด"
            if (f_past_valid && !rst && !f_past_rst && !f_async_reset_hit) begin
                if (f_past_en) begin
                    assert($onehot(ptr_g ^ f_past_ptr_g)); // ถ้าเดินหน้า ต้องเปลี่ยน 1 บิต
                end else begin
                    assert(ptr_g == f_past_ptr_g);         // ถ้าหยุด ต้องหยุดนิ่งๆ
                end
                
                // ตรวจสอบการพลิกกลับของบิตสูงสุด (MSB)
                if (bin[ADDR_WIDTH] != f_past_bin[ADDR_WIDTH]) begin
                    assert(ptr_g[ADDR_WIDTH] != f_past_ptr_g[ADDR_WIDTH]);
                end
            end
        end

        // -------------------------------------------------------------
        // 4. Liveness / Cover
        // -------------------------------------------------------------
        always @(posedge clk) begin
            if (f_past_valid && !rst && !f_past_rst && !f_async_reset_hit) begin
                cover (ptr_g == 0 && f_past_ptr_g != 0); // คลุมการ Wrap-around
            end
        end
        `endif
    `endif

endmodule
