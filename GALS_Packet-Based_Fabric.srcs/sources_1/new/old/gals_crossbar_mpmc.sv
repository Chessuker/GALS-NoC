`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/17/2026 06:02:08 PM
// Design Name: 
// Module Name: gals_crossbar_mpmc
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


module gals_crossbar_mpmc #(
    parameter NUM_PRODUCERS = 4,
    parameter NUM_CONSUMERS = 4,
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 12
)(
    input  logic clk,
    input  logic rst_n,

    // ฝั่ง Producers (อาร์เรย์ของ FIFO)
    input  logic [NUM_PRODUCERS-1:0]                   p_empty,
    input  logic [NUM_PRODUCERS-1:0][DATA_WIDTH-1:0]   p_data,
    output logic [NUM_PRODUCERS-1:0]                   p_pop_en, // สั่งดึงของออกจากคิว P

    // ฝั่ง Consumers
    input  logic [NUM_CONSUMERS-1:0]                   c_ready,
    output logic [NUM_CONSUMERS-1:0]                   c_valid,
    output logic [NUM_CONSUMERS-1:0][DATA_WIDTH-1:0]   c_data,

    // 🔴 Dynamic Subscription Matrix: C ตัวไหน ต้องการฟัง P ตัวไหน
    // โครงสร้าง [Consumer_ID][Producer_ID]
    input  logic [NUM_CONSUMERS-1:0][NUM_PRODUCERS-1:0] subscription_matrix 
);

    genvar p, c;

    // ==========================================
    // 1. กระจายข้อมูลจาก P ไปหา C ทุกตัวที่ Sub ไว้ (Data Broadcast)
    // ==========================================
    generate
        for (c = 0; c < NUM_CONSUMERS; c++) begin : gen_c_data
            always_comb begin
                c_valid[c] = 1'b0;
                c_data[c]  = '0;
                
                // สแกนว่า C ตัวนี้กำลัง Sub ใครอยู่ และ P ตัวนั้นมีของไหม
                for (int i = 0; i < NUM_PRODUCERS; i++) begin
                    if (subscription_matrix[c][i] == 1'b1 && !p_empty[i]) begin
                        c_valid[c] = 1'b1;
                        c_data[c]  = p_data[i];
                    end
                end
            end
        end
    endgenerate

    // ==========================================
    // 2. ลอจิกการกดปุ่ม POP (Wait for Everyone)
    // ==========================================
    generate
        for (p = 0; p < NUM_PRODUCERS; p++) begin : gen_p_pop
            logic all_subscribers_ready;
            
            always_comb begin
                all_subscribers_ready = 1'b1; // ตั้งต้นเป็นจริงไว้ก่อน
                
                // เช็ค C ทุกตัวในระบบ
                for (int j = 0; j < NUM_CONSUMERS; j++) begin
                    // ถ้า C ตัวนี้กด Sub P[p] เอาไว้ "แต่" ยังไม่พร้อมรับ (c_ready = 0)
                    if (subscription_matrix[j][p] == 1'b1 && c_ready[j] == 1'b0) begin
                        all_subscribers_ready = 1'b0; // เบรกไว้! ห้าม POP เด็ดขาด!
                    end
                end
                
                // จะ POP ก็ต่อเมื่อ P มีของ และ C ทุกคนที่อยากได้ของ "พร้อมแล้ว"
                p_pop_en[p] = !p_empty[p] && all_subscribers_ready;
            end
        end
    endgenerate

endmodule
