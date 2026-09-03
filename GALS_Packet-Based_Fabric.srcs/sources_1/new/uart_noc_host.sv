`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/21/2026 06:19:29 PM
// Design Name: 
// Module Name: uart_noc_host
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


module uart_noc_host #(
    parameter CLK_FREQ  = 100_000_000,
    parameter BAUD_RATE = 3_000_000
)(
    input  logic clk,
    input  logic rst_n,
 
    input  logic uart_rxd,
    output logic uart_txd,
 
    output logic [7:0] tx_tdata,
    output logic [3:0] tx_tdest,
    output logic [1:0] tx_tid,
    output logic       tx_tlast,
    output logic       tx_tvalid,
    input  logic [1:0] tx_tready,
 
    input  logic [7:0] rx_tdata,
    input  logic [3:0] rx_tdest,
    input  logic [1:0] rx_tid,
    input  logic       rx_tlast,
    input  logic       rx_tvalid,
    output logic [1:0] rx_tready
);
 
    //-------------------------------------------------------------- UART RX
    logic [7:0] uart_rx_data;
    logic       uart_rx_valid;
 
    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) rx_inst (
        .clk(clk), .rst(!rst_n), .rx(uart_rxd),
        .rx_data(uart_rx_data), .rx_valid(uart_rx_valid)
    );
 
    logic [7:0] rx_fifo_rdata;
    logic       rx_fifo_empty;
    logic       rx_fifo_full;
    logic       rx_fifo_r_en;      // <-- ตอนนี้เป็น combinational แล้ว
 
    sync_fifo #(.DATA_WIDTH(8), .DEPTH(256)) uart_rx_buffer (
        .clk(clk), .rst_n(rst_n),
        .w_en(uart_rx_valid),
        .w_data(uart_rx_data),
        .r_en(rx_fifo_r_en),
        .r_data(rx_fifo_rdata),
        .full(rx_fifo_full),
        .empty(rx_fifo_empty)
    );
 
    //-------------------------------------------------------------- UART TX
    logic [7:0] uart_tx_data;
    logic       uart_tx_valid;
    logic       uart_tx_ready;
 
    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) tx_inst (
        .clk(clk), .rst(!rst_n),
        .tx_data(uart_tx_data), .tx_valid(uart_tx_valid),
        .tx(uart_txd), .tx_ready(uart_tx_ready)
    );
 
    //=========================================================================
    // UART -> NoC parser  (2 bytes = 1 flit : header, payload)
    //=========================================================================
    logic [7:0] header_reg;
    enum logic [1:0] {P_WAIT_B1, P_WAIT_B2, P_PUSH_NOC} p_state;
 
    // <<< FIX 2 >>> pop ในรอบเดียวกับที่อ่านค่า (FWFT)
    always_comb begin
        rx_fifo_r_en = 1'b0;
        if (!rx_fifo_empty && (p_state == P_WAIT_B1 || p_state == P_WAIT_B2))
            rx_fifo_r_en = 1'b1;
    end
 
    logic vc_ready;
    assign vc_ready = (tx_tid[1] & tx_tready[1]) | (tx_tid[0] & tx_tready[0]);
 
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p_state    <= P_WAIT_B1;
            tx_tvalid  <= 1'b0;
            tx_tdata   <= '0;
            tx_tdest   <= '0;
            tx_tid     <= '0;
            tx_tlast   <= 1'b0;
            header_reg <= '0;
        end else begin
            case (p_state)
                P_WAIT_B1: begin
                    if (!rx_fifo_empty) begin
                        header_reg <= rx_fifo_rdata;   // byte0 = header
                        p_state    <= P_WAIT_B2;
                    end
                end
 
                P_WAIT_B2: begin
                    if (!rx_fifo_empty) begin
                        tx_tdata  <= rx_fifo_rdata;    // byte1 = payload (ตอนนี้ถูกแล้ว)
                        tx_tdest  <= header_reg[3:0];
                        tx_tid    <= header_reg[6:5];
                        tx_tlast  <= header_reg[7];
                        tx_tvalid <= 1'b1;
                        p_state   <= P_PUSH_NOC;
                    end
                end
 
                P_PUSH_NOC: begin
                    if (vc_ready) begin
                        tx_tvalid <= 1'b0;
                        p_state   <= P_WAIT_B1;
                    end
                end
            endcase
        end
    end
 
    //=========================================================================
    // NoC -> UART  (1 flit = 2 bytes)
    //=========================================================================
    enum logic [1:0] {D_IDLE, D_SEND_HEADER, D_SEND_DATA} d_state;
    logic [7:0] noc_data_reg;
 
    assign rx_tready = (d_state == D_IDLE) ? 2'b11 : 2'b00;
 
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            d_state       <= D_IDLE;
            uart_tx_valid <= 1'b0;
            uart_tx_data  <= '0;
            noc_data_reg  <= '0;
        end else begin
            // <<< FIX 3 >>> ไม่มี default clear ของ uart_tx_valid อีกต่อไป
            case (d_state)
                D_IDLE: begin
                    uart_tx_valid <= 1'b0;
                    if (rx_tvalid && (|rx_tready)) begin
                        noc_data_reg  <= rx_tdata;
                        uart_tx_data  <= {rx_tlast, rx_tid, 1'b0, rx_tdest};
                        uart_tx_valid <= 1'b1;
                        d_state       <= D_SEND_HEADER;
                    end
                end
 
                D_SEND_HEADER: begin
                    if (uart_tx_valid && uart_tx_ready) begin   // header ถูกรับแล้ว
                        uart_tx_data  <= noc_data_reg;
                        uart_tx_valid <= 1'b1;
                        d_state       <= D_SEND_DATA;
                    end
                end
 
                D_SEND_DATA: begin
                    if (uart_tx_valid && uart_tx_ready) begin   // payload ถูกรับแล้ว
                        uart_tx_valid <= 1'b0;
                        d_state       <= D_IDLE;
                    end
                end
 
                default: d_state <= D_IDLE;
            endcase
        end
    end
 
    //-------------------------------------------------------------- ILA taps
    //-------------------------------------------------------------- ILA taps
    // 🔴 เดิมบล็อกนี้ครอบด้วย `ifdef DEBUG_BUILD ซึ่งไม่มีใครนิยามไว้ที่ไหนเลย
    //    ผล: UART build ไม่มี instrumentation แม้แต่เส้นเดียว (HANDOFF gotcha 5)
    //    define ที่ต้อง "จำไว้ตั้ง" หลุดไปแล้วหนึ่งครั้ง จึงเอาออกทั้งอัน
    //    ให้ probe ติดมาเสมอ แบบเดียวกับ traffic_node_agent ที่พิสูจน์แล้วว่าใช้ได้
    //
    //    และต้องมี dont_touch คู่กับ mark_debug ด้วย (gotcha 1):
    //    เส้นพวกนี้ไม่มี fanout จริง synthesis จะกวาดทิ้งก่อน Set Up Debug จะเห็น
    //    ใส่ mark_debug เฉยๆ ไม่พอ — นี่คือเหตุผลที่ 668 vs 924 เคยเกิดขึ้น
    (* mark_debug = "true", dont_touch = "true" *) logic        rx_tvalid_dbg;
    (* mark_debug = "true", dont_touch = "true" *) logic [7:0]  rx_tdata_dbg;
    (* mark_debug = "true", dont_touch = "true" *) logic [1:0]  rx_tid_dbg;
    (* mark_debug = "true", dont_touch = "true" *) logic [1:0]  d_state_dbg;
    (* mark_debug = "true", dont_touch = "true" *) logic [7:0]  noc_data_reg_dbg;
    (* mark_debug = "true", dont_touch = "true" *) logic        uart_tx_valid_dbg;
    (* mark_debug = "true", dont_touch = "true" *) logic        uart_tx_ready_dbg;
    (* mark_debug = "true", dont_touch = "true" *) logic [1:0]  p_state_dbg;
    (* mark_debug = "true", dont_touch = "true" *) logic [7:0]  tx_tdata_dbg;

    assign rx_tvalid_dbg     = rx_tvalid;
    assign rx_tdata_dbg      = rx_tdata;
    assign rx_tid_dbg        = rx_tid;
    assign d_state_dbg       = d_state;
    assign noc_data_reg_dbg  = noc_data_reg;
    assign uart_tx_valid_dbg = uart_tx_valid;
    assign uart_tx_ready_dbg = uart_tx_ready;
    assign p_state_dbg       = p_state;
    assign tx_tdata_dbg      = tx_tdata;
 
endmodule
