`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Thawat Boonsuk
// 
// Create Date: 04/07/2026 09:21:46 PM
// Design Name: 
// Module Name: async_fifo
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


module async_fifo#(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
)(
    input logic wclk,
    input logic wrst_n,
    input logic w_en,
    input logic [DATA_WIDTH-1:0] wdata,
    output logic wfull,
    (* DONT_TOUCH = "TRUE" *) output logic [ADDR_WIDTH:0] w_level,
    
    input logic rclk,
    input logic rrst_n,
    input logic r_en,
    output logic [DATA_WIDTH-1:0] rdata,
    output logic rempty,

    output logic almost_full,
    input  logic [ADDR_WIDTH:0] prog_full_thresh, 

    output logic almost_empty,
    input  logic [ADDR_WIDTH:0] prog_empty_thresh,
    
    output logic ecc_single_err,
    output logic ecc_double_err
);
    
    logic [ADDR_WIDTH-1:0] waddr, raddr;
    logic [ADDR_WIDTH:0] wptr_g, rptr_g;
    logic [ADDR_WIDTH:0] wptr_g_sync, rptr_g_sync;

    // =================================================================
    // 🟢 แยก RAM: TDATA เข้า ECC, TLAST+TDEST เข้า RAM ธรรมดา
    // =================================================================
    `ifdef FORMAL
        dual_port_ram #(
            .DATA_WIDTH(DATA_WIDTH),
            .ADDR_WIDTH(ADDR_WIDTH)
        ) dp_ram (
            .wclk(wclk), .w_en(w_en && !wfull), .waddr(waddr), .wdata(wdata),
            .rclk(rclk), .r_en(r_en && !rempty), .raddr(raddr), .rdata(rdata)
        );
        assign ecc_single_err = 1'b0;
        assign ecc_double_err = 1'b0;

    `else
        logic [7:0] rdata_ecc;

        // 1. RAM สำหรับ Payload (8 บิตล่าง) - มี ECC ป้องกัน Error
        dual_port_ram_ecc #(
            .DATA_WIDTH(8),
            .ADDR_WIDTH(ADDR_WIDTH)
        ) dp_ram_ecc_inst (
            .wclk(wclk),
            .w_en(w_en && !wfull),
            .waddr(waddr),
            .wdata(wdata[7:0]), // 🟢 ใส่แค่ 8 บิต
            .rclk(rclk),
            .r_en(r_en && !rempty),
            .raddr(raddr),
            .rdata(rdata_ecc),
            .ecc_single_err(ecc_single_err),
            .ecc_double_err(ecc_double_err)
        );

        // 2. RAM สำหรับ Control Bits (บิตที่ 8 ขึ้นไป) - ไม่มี ECC
        generate
            if (DATA_WIDTH > 8) begin : GEN_CTRL_RAM
                logic [(DATA_WIDTH-8)-1:0] rdata_ctrl;
                
                dual_port_ram #(
                    .DATA_WIDTH(DATA_WIDTH - 8),
                    .ADDR_WIDTH(ADDR_WIDTH)
                ) dp_ram_ctrl_inst (
                    .wclk(wclk),
                    .w_en(w_en && !wfull),
                    .waddr(waddr),
                    .wdata(wdata[DATA_WIDTH-1 : 8]), // 🟢 ใส่ 5 บิตที่เหลือ (TLAST, TDEST)
                    .rclk(rclk),
                    .r_en(r_en && !rempty),
                    .raddr(raddr),
                    .rdata(rdata_ctrl)
                );
                
                // 🟢 ประกอบร่าง 13 บิตกลับคืนมา
                assign rdata = {rdata_ctrl, rdata_ecc};
                
            end else begin : GEN_NO_CTRL
                assign rdata = rdata_ecc;
            end
        endgenerate
    `endif
    
    // =================================================================
    // FIFO Pointers & Gray Counters (เหมือนเดิม)
    // =================================================================
    gray_counter #(ADDR_WIDTH) w_cnt (
        .clk(wclk), .rst(!wrst_n), .en(w_en && !wfull), .ptr_g(wptr_g), .addr(waddr)
    );
    gray_counter #(ADDR_WIDTH) r_cnt (
        .clk(rclk), .rst(!rrst_n), .en(r_en && !rempty), .ptr_g(rptr_g), .addr(raddr)
    );
    sync_2stage #(ADDR_WIDTH+1) sync_w2r (
        .clk(rclk), .rst(!rrst_n), .d(wptr_g), .q(wptr_g_sync)
    );
    sync_2stage #(ADDR_WIDTH+1) sync_r2w (
        .clk(wclk), .rst(!wrst_n), .d(rptr_g), .q(rptr_g_sync)
    );

    assign rempty = (wptr_g_sync == rptr_g);
    assign wfull = (wptr_g == {~rptr_g_sync[ADDR_WIDTH], ~rptr_g_sync[ADDR_WIDTH-1], rptr_g_sync[ADDR_WIDTH-2:0]});

    // =================================================================
    // Level & Watermark Calculation (เหมือนเดิม)
    // =================================================================
    logic [ADDR_WIDTH:0] wptr_bin;
    logic [ADDR_WIDTH:0] rptr_bin_sync;

    always_comb begin
        wptr_bin[ADDR_WIDTH] = wptr_g[ADDR_WIDTH];
        for (int i = ADDR_WIDTH-1; i >= 0; i--) wptr_bin[i] = wptr_bin[i+1] ^ wptr_g[i];
    end

    always_comb begin
        rptr_bin_sync[ADDR_WIDTH] = rptr_g_sync[ADDR_WIDTH];
        for (int i = ADDR_WIDTH-1; i >= 0; i--) rptr_bin_sync[i] = rptr_bin_sync[i+1] ^ rptr_g_sync[i];
    end

    assign w_level = wptr_bin - rptr_bin_sync;
    assign almost_full = (w_level >= prog_full_thresh);

    logic [ADDR_WIDTH:0] rptr_bin;
    logic [ADDR_WIDTH:0] wptr_bin_sync;

    always_comb begin
        rptr_bin[ADDR_WIDTH] = rptr_g[ADDR_WIDTH];
        for (int i = ADDR_WIDTH-1; i >= 0; i--) rptr_bin[i] = rptr_bin[i+1] ^ rptr_g[i];
    end

    always_comb begin
        wptr_bin_sync[ADDR_WIDTH] = wptr_g_sync[ADDR_WIDTH];
        for (int i = ADDR_WIDTH-1; i >= 0; i--) wptr_bin_sync[i] = wptr_bin_sync[i+1] ^ wptr_g_sync[i];
    end

    logic [ADDR_WIDTH:0] r_level;
    assign r_level = wptr_bin_sync - rptr_bin;
    assign almost_empty = (r_level <= prog_empty_thresh);

endmodule
