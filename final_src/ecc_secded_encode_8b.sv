`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/03/2026 11:55:57 PM
// Design Name: 
// Module Name: ecc_secded_encode_8b
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


module ecc_secded_encode_8b (
    input  logic [7:0]  data_in,
    output logic [12:0] encoded_out // {Overall Parity (1), Data (8), Hamming (4)}
);
    logic p1, p2, p4, p8, p0;
    
    // คำนวณ Hamming Parity (XOR บิตตามตำแหน่ง)
    assign p1 = data_in[0] ^ data_in[1] ^ data_in[3] ^ data_in[4] ^ data_in[6];
    assign p2 = data_in[0] ^ data_in[2] ^ data_in[3] ^ data_in[5] ^ data_in[6];
    assign p4 = data_in[1] ^ data_in[2] ^ data_in[3] ^ data_in[7];
    assign p8 = data_in[4] ^ data_in[5] ^ data_in[6] ^ data_in[7];
    
    // ประกอบร่าง 12-bit แรก
    logic [11:0] hamming_word;
    assign hamming_word = {data_in[7:4], p8, data_in[3:1], p4, data_in[0], p2, p1};
    
    // คำนวณ Overall Parity (สำหรับเช็ค Double Error)
    assign p0 = ^hamming_word; // XOR ทุกบิตเข้าด้วยกัน
    
    assign encoded_out = {p0, hamming_word};
endmodule
