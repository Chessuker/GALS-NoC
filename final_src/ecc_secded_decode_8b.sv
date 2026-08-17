`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/04/2026 12:11:52 AM
// Design Name: 
// Module Name: ecc_secded_decode_8b
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


module ecc_secded_decode_8b (
    input  logic [12:0] encoded_in,
    output logic [7:0]  data_out,
    output logic        single_err,
    output logic        double_err
);
    logic p0_in;
    logic [11:0] word_in;
    assign p0_in = encoded_in[12];
    assign word_in = encoded_in[11:0];

    // คำนวณ Syndrome (หาว่าบิตไหนผิด)
    logic s1, s2, s4, s8;
    assign s1 = word_in[0] ^ word_in[2] ^ word_in[4] ^ word_in[6] ^ word_in[8] ^ word_in[10];
    assign s2 = word_in[1] ^ word_in[2] ^ word_in[5] ^ word_in[6] ^ word_in[9] ^ word_in[10];
    assign s4 = word_in[3] ^ word_in[4] ^ word_in[5] ^ word_in[6] ^ word_in[11];
    assign s8 = word_in[7] ^ word_in[8] ^ word_in[9] ^ word_in[10] ^ word_in[11];
    
    logic [3:0] syndrome;
    assign syndrome = {s8, s4, s2, s1};
    
    // เช็ค Overall Parity
    logic overall_parity_calc;
    assign overall_parity_calc = ^word_in;
    logic parity_mismatch;
    assign parity_mismatch = (overall_parity_calc != p0_in);

    // วิเคราะห์สถานการณ์
    always_comb begin
        single_err = 1'b0;
        double_err = 1'b0;
        
        if (syndrome != 0) begin
            if (parity_mismatch) begin
                single_err = 1'b1; // Syndrome ชี้เป้าบิตที่พัง 1 บิต (ซ่อมได้)
            end else begin
                double_err = 1'b1; // Syndrome ผิดปกติ แต่ Parity รวมดันถูก = พัง 2 บิต! (ซ่อมไม่ได้)
            end
        end else if (parity_mismatch) begin
            single_err = 1'b1; // พังที่ตัวบิต Overall Parity เอง
        end
    end

    // วงจรพลิกบิตกลับ (Corrector)
    logic [11:0] corrected_word;
    always_comb begin
        corrected_word = word_in;
        if (single_err && syndrome != 0) begin
            corrected_word[syndrome - 1] = ~corrected_word[syndrome - 1]; // พลิกบิตที่พังกลับ!
        end
    end

    // สกัด Data บริสุทธิ์ออกมา
    assign data_out = {corrected_word[11:8], corrected_word[6:4], corrected_word[2]};
endmodule
