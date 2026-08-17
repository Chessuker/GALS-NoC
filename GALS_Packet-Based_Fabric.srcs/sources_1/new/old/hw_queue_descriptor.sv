`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Thawat Boonsuk
// 
// Create Date: 04/11/2026 11:09:34 AM
// Design Name: 
// Module Name: hw_queue_descriptor
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


module hw_queue_descriptor #(
    parameter NUM_PRODUCERS = 3,
    parameter DATA_WIDTH = 8
)(
    input  logic clk,
    input  logic rst_n,
    
    // พอร์ตรับคำขอ (Request) จาก Producers
    input  logic [NUM_PRODUCERS-1:0] req,
    output logic [NUM_PRODUCERS-1:0] grant,
    
    // พอร์ตรับข้อมูล
    input  logic [(NUM_PRODUCERS * DATA_WIDTH)-1:0] prod_data,
    
    // พอร์ตส่งข้อมูลลง FIFO
    input  logic fifo_wfull,
    output logic fifo_w_en,
    output logic [DATA_WIDTH-1:0] fifo_wdata
);

    logic [NUM_PRODUCERS-1:0] mask;
    logic [NUM_PRODUCERS-1:0] masked_req;
    logic [NUM_PRODUCERS-1:0] masked_grant;
    logic [NUM_PRODUCERS-1:0] unmasked_grant;
    logic [NUM_PRODUCERS-1:0] raw_grant;

    // =================================================================
    // 1. ลอจิกการหาคิว (Combinational Arbiter)
    // =================================================================
    
    // 1.1 บัง (Mask) คำขอของคนที่คิวต่ำกว่าหรือเท่ากับคนที่เพิ่งได้สิทธิ์รอบที่แล้ว
    assign masked_req = req & mask;

    // 1.2 ใช้เทคนิค 2's Complement (x & -x) เพื่อหาบิต '1' ตัวแรกสุดจากทางขวา
    // นี่คือ Fixed Priority Encoder แบบไม่ต้องใช้ if-else หรือ loop
    assign masked_grant   = masked_req & (~masked_req + 1'b1);
    assign unmasked_grant = req & (~req + 1'b1);

    // 1.3 ถ้ามีคนขอคิวในกลุ่มที่ยังไม่ถูก Mask ให้คิวนั้นชนะ 
    // แต่ถ้าไม่มี (วนครบรอบแล้ว) ให้กลับไปกวาดกลุ่ม Unmasked ตั้งแต่ต้น
    assign raw_grant = (masked_req != 0) ? masked_grant : unmasked_grant;

    // 1.4 ถ้าคิวเต็ม (wfull) หรือไม่มีใครขอมาเลย ก็ไม่ต้องออก Grant
    assign grant = (fifo_wfull || req == 0) ? '0 : raw_grant;

    // =================================================================
    // 2. อัปเดต Mask สำหรับรอบถัดไป (Sequential Logic)
    // =================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mask <= {NUM_PRODUCERS{1'b1}}; 
        end else begin
            // *สำคัญมาก:* ต้องอัปเดต Mask ตาม raw_grant (คนที่ชนะการประมูล) 
            // ไม่ใช่ grant (คนที่ได้ส่งจริง) และต้องอัปเดตเฉพาะตอนที่มีคนขอและส่งออกได้สำเร็จเท่านั้น
            if (raw_grant != 0 && !fifo_wfull) begin
                mask <= ~(raw_grant | (raw_grant - 1'b1));
            end
        end
    end

    // =================================================================
    // 3. ลอจิก Data Path (เขียนลง FIFO ทันทีใน Cycle เดียวกัน)
    // =================================================================
    assign fifo_w_en = (grant != 0) && !fifo_wfull;

    // MUX แบบ One-Hot: เร็วกว่า MUX ปกติและใช้เกทน้อยกว่า
    always_comb begin
        fifo_wdata = '0;
        for (int i = 0; i < NUM_PRODUCERS; i++) begin
            if (grant[i]) begin
                // ใช้ตัวดำเนินการ +: (ดึงข้อมูลขึ้นไป DATA_WIDTH บิต เริ่มจากฐาน)
                fifo_wdata |= prod_data[i * DATA_WIDTH +: DATA_WIDTH];
            end
        end
    end

    // =================================================================
    // FORMAL VERIFICATION (PROPERTIES & ASSERTIONS)
    // =================================================================
    `ifdef FORMAL
        
        // 1. Mutual Exclusion
        always_comb begin
            assert($onehot0(grant)); 
        end

        // 2. Grant Validity
        always_comb begin
            if (grant != 0) begin
                assert((grant & req) == grant);
            end
        end

        // 3. Backpressure Compliance
        always_comb begin
            if (fifo_wfull) begin
                assert(grant == '0);
            end
        end

        // 4. Work Conservation
        always_comb begin
            if (req != 0 && !fifo_wfull) begin
                assert(grant != '0);
            end
        end

        // 5. Reachability (Parameterized)
        generate
            for (genvar j = 0; j < NUM_PRODUCERS; j++) begin : gen_cover_grant
                always_comb begin
                    cover(grant == (1 << j)); 
                end
            end
        endgenerate

    `endif

endmodule
