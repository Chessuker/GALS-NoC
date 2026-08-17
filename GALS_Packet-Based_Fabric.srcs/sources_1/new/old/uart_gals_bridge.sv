`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/09/2026 04:39:52 PM
// Design Name: 
// Module Name: uart_gals_bridge
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


module uart_gals_bridge (
    input  logic CLK100MHZ,   // Pin E3
    input  logic btn_rst,     // Pin D9 (Active High Reset)
    input  logic [2:0] sw,    // 🔴 เพิ่มพอร์ตสวิตช์: sw[0]->P0, sw[1]->P1, sw[2]->P2
    input  logic uart_txd_in, // RX จากคอมพิวเตอร์
    output logic uart_rxd_out,// TX กลับไปคอมพิวเตอร์
    output logic [3:0] led    // แสดงสถานะคิว
);

    // ==========================================
    // 1. Clock Generation & Reset
    // ==========================================
    logic clk_P0, clk_P1, clk_P2, clk_B, clk_locked;
    clk_wiz_0 clk_gen (
        .clk_in1(CLK100MHZ), .reset(btn_rst), .locked(clk_locked),
        .clk_out1(clk_P0), .clk_out2(clk_P1), .clk_out3(clk_P2), .clk_out4(clk_B)
    );

    logic rst_P0_n, rst_P1_n, rst_P2_n, rst_B_n;
    always_ff @(posedge clk_P0) rst_P0_n <= clk_locked;
    always_ff @(posedge clk_P1) rst_P1_n <= clk_locked;
    always_ff @(posedge clk_P2) rst_P2_n <= clk_locked;
    always_ff @(posedge clk_B)  rst_B_n  <= clk_locked;

    // ==========================================
    // 1.5 Synchronize Switches to clk_P1 Domain
    // ==========================================
    // เนื่องจากสวิตช์เป็น Asynchronous เราต้องจับซิงค์เข้า clk_P1 ก่อนใช้งาน
    logic [2:0] sw_r1, sw_sync;
    always_ff @(posedge clk_P1 or negedge rst_P1_n) begin
        if (!rst_P1_n) begin
            sw_r1 <= 3'b111; // เริ่มต้นให้เปิดใช้งานทั้งหมด
            sw_sync <= 3'b111;
        end else begin
            sw_r1 <= sw;
            sw_sync <= sw_r1;
        end
    end

    // ==========================================
    // 2. UART Receiver (100 MHz - clk_P1 domain)
    // ==========================================
    logic [7:0] rx_data;
    logic rx_valid;
    uart_rx #(.CLK_FREQ(100_000_000), .BAUD_RATE(3000000)) rx_inst (
        .clk(clk_P1), .rst(!rst_P1_n), .rx(uart_txd_in),
        .rx_data(rx_data), .rx_valid(rx_valid)
    );

    // ==========================================
    // 3. The Dispatcher (กระจายงานตาม Header)
    // ==========================================
    logic p0_req, p1_valid, p2_req;
    logic [7:0] dispatch_data;
    logic cmd_ready_reg;

    always_ff @(posedge clk_P1 or negedge rst_P1_n) begin
        if (!rst_P1_n) begin
            p0_req <= 0; p1_valid <= 0; p2_req <= 0;
            dispatch_data <= 0; 
            cmd_ready_reg <= 1'b1; // 🔴 บังคับเปิดวาล์วเสมอเมื่อรีเซ็ต
        end else begin
            p0_req <= 0; p1_valid <= 0; p2_req <= 0;
            
            // 🔴 ล็อกให้วาล์วเปิดค้างไว้ตลอดกาล
            cmd_ready_reg <= 1'b1; 

            if (rx_valid) begin
                dispatch_data <= rx_data;
                case (rx_data[7:6])
                    2'b00: p0_req <= 1'b1;   
                    2'b01: p1_valid <= 1'b1; 
                    2'b10: p2_req <= 1'b1;   
                    // 🔴 ลบเงื่อนไข 2'b11 ทิ้งไปเลย! ไม่รับคำสั่งปิดวาล์วอีกต่อไป
                endcase
            end
        end
    end

    // 🔴 จุดแก้ไข: ใช้สัญญาณจากสวิตช์ (sw_sync) มาดักทางสัญญาณ valid ก่อนส่งเข้าคิว
    logic p0_valid, p2_valid;
    pulse_sync sync_p0 (.clk_a(clk_P1), .rst_a(!rst_P1_n), .pulse_a(p0_req & sw_sync[0]), .clk_b(clk_P0), .rst_b(!rst_P0_n), .pulse_b(p0_valid));
    pulse_sync sync_p2 (.clk_a(clk_P1), .rst_a(!rst_P1_n), .pulse_a(p2_req & sw_sync[2]), .clk_b(clk_P2), .rst_b(!rst_P2_n), .pulse_b(p2_valid));

    logic p1_valid_gated;
    assign p1_valid_gated = p1_valid & sw_sync[1];

    (* ASYNC_REG = "TRUE" *) logic [1:0] consumer_ready_sync;
    always_ff @(posedge clk_B or negedge rst_B_n) begin
        if (!rst_B_n) consumer_ready_sync <= 0;
        else consumer_ready_sync <= {consumer_ready_sync[0], cmd_ready_reg};
    end

    // ==========================================
    // 4. Core GALS MPMC Instance (DUT)
    // ==========================================
    logic consumer_ready;
    logic consumer_valid;
    logic [7:0] consumer_data;
    logic p0_full, p1_full, p2_full;
    logic p0_almost_full, p1_almost_full, p2_almost_full;
    logic [2:0] ecc_single, ecc_double;

    gals_top_mpmc dut (
        .clk_P0(clk_P0), .rst_P0_n(rst_P0_n), .p0_valid(p0_valid), .p0_data(dispatch_data), .p0_full(p0_full), .p0_almost_full(p0_almost_full),
        .clk_P1(clk_P1), .rst_P1_n(rst_P1_n), .p1_valid(p1_valid_gated), .p1_data(dispatch_data), .p1_full(p1_full), .p1_almost_full(p1_almost_full), // 🔴 ใช้ p1_valid_gated
        .clk_P2(clk_P2), .rst_P2_n(rst_P2_n), .p2_valid(p2_valid), .p2_data(dispatch_data), .p2_full(p2_full), .p2_almost_full(p2_almost_full),
        .clk_B(clk_B),   .rst_B_n(rst_B_n),   
        .consumer_ready(consumer_ready),
        .consumer_valid(consumer_valid), 
        .consumer_data(consumer_data),
        .p_ecc_single_err(ecc_single), 
        .p_ecc_double_err(ecc_double)
    );

    // ==========================================
    // 5. UART TX & Traffic Arbiter (4-State Bulletproof FSM)
    // ==========================================
    logic tx_ready;
    logic tx_valid_mux;
    logic [7:0] tx_data_mux;
    
    enum logic [1:0] {TX_IDLE, TX_TRIGGER, TX_WAIT_BUSY, TX_WAIT_READY} tx_state;

    always_ff @(posedge clk_B or negedge rst_B_n) begin
        if (!rst_B_n) begin
            tx_state <= TX_IDLE;
            tx_valid_mux <= 0;
            tx_data_mux <= 0;
        end else begin
            case (tx_state)
                TX_IDLE: begin
                    if (consumer_valid && tx_ready) begin
                        tx_valid_mux <= 1;
                        tx_data_mux <= consumer_data; 
                        tx_state <= TX_TRIGGER;          
                    end
                end
                TX_TRIGGER: begin
                    tx_valid_mux <= 0; 
                    tx_state <= TX_WAIT_BUSY;
                end
                TX_WAIT_BUSY: begin
                    if (!tx_ready) tx_state <= TX_WAIT_READY; 
                end
                TX_WAIT_READY: begin
                    if (tx_ready) tx_state <= TX_IDLE; 
                end
            endcase
        end
    end

    assign consumer_ready = consumer_ready_sync[1] & (tx_state == TX_IDLE) & tx_ready;

    uart_tx #(.CLK_FREQ(166_666_667), .BAUD_RATE(3000000)) tx_inst (
        .clk(clk_B), .rst(!rst_B_n),
        .tx_data(tx_data_mux), .tx_valid(tx_valid_mux),
        .tx(uart_rxd_out), .tx_ready(tx_ready)
    );

    // ==========================================
    // 6. LED Status Mapping
    // ==========================================
    assign led[0] = p0_full;
    assign led[1] = p1_full;
    assign led[2] = p2_full;
    assign led[3] = (|ecc_single) || (|ecc_double);

endmodule