`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/09/2026 04:37:51 PM
// Design Name: 
// Module Name: uart_transceiver
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


module uart_rx #(parameter CLK_FREQ = 100_000_000, BAUD_RATE = 115200) (
    input  logic clk, rst, rx,
    output logic [7:0] rx_data,
    output logic rx_valid
);
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
    
    enum logic [1:0] {IDLE, START, DATA, STOP} state;
    logic [15:0] clk_cnt;
    logic [2:0]  bit_cnt;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE; rx_valid <= 0; rx_data <= 0;
            clk_cnt <= 0; bit_cnt <= 0;
        end else begin
            rx_valid <= 0;
            case (state)
                IDLE: begin
                    clk_cnt <= 0; bit_cnt <= 0;
                    if (rx == 0) state <= START; // ตรวจจับ Start Bit
                end
                START: begin
                    if (clk_cnt == CLKS_PER_BIT/2) begin
                        if (rx == 0) begin clk_cnt <= 0; state <= DATA; end
                        else state <= IDLE; // False alarm
                    end else clk_cnt <= clk_cnt + 1;
                end
                DATA: begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= 0;
                        rx_data[bit_cnt] <= rx; // เก็บข้อมูลทีละบิต
                        if (bit_cnt == 7) state <= STOP;
                        else bit_cnt <= bit_cnt + 1;
                    end else clk_cnt <= clk_cnt + 1;
                end
                STOP: begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        rx_valid <= 1; // ส่งสัญญาณว่าได้รับข้อมูลครบ 1 Byte
                        state <= IDLE;
                    end else clk_cnt <= clk_cnt + 1;
                end
            endcase
        end
    end
endmodule

module uart_tx #(parameter CLK_FREQ = 100_000_000, BAUD_RATE = 115200) (
    input  logic clk, rst,
    input  logic [7:0] tx_data,
    input  logic tx_valid,
    output logic tx,
    output logic tx_ready
);
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;
 
    enum logic [1:0] {IDLE, START, DATA, STOP} state;
    logic [15:0] clk_cnt;
    logic [2:0]  bit_cnt;
    logic [7:0]  data_reg;
 
    // <<< FIX 1 >>>
    assign tx_ready = (state == IDLE);
 
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE; tx <= 1; clk_cnt <= 0; bit_cnt <= 0; data_reg <= 0;
        end else begin
            case (state)
                IDLE: begin
                    tx <= 1; clk_cnt <= 0; bit_cnt <= 0;
                    if (tx_valid) begin
                        data_reg <= tx_data;
                        state    <= START;
                    end
                end
                START: begin
                    tx <= 0;
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= 0; state <= DATA;
                    end else clk_cnt <= clk_cnt + 1;
                end
                DATA: begin
                    tx <= data_reg[bit_cnt];
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= 0;
                        if (bit_cnt == 7) state <= STOP;
                        else bit_cnt <= bit_cnt + 1;
                    end else clk_cnt <= clk_cnt + 1;
                end
                STOP: begin
                    tx <= 1;
                    if (clk_cnt == CLKS_PER_BIT-1) state <= IDLE;
                    else clk_cnt <= clk_cnt + 1;
                end
            endcase
        end
    end
endmodule
