`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/04/2026 04:34:18 PM
// Design Name: 
// Module Name: async_fifo_upsize
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


module async_fifo_upsize #(
    // อัตราส่วน 1:4 (Write 8-bit, Read 32-bit)
    parameter W_DATA_WIDTH = 8,
    parameter W_ADDR_WIDTH = 6, // ความจุ 64 ช่อง (8-bit)
    
    parameter R_DATA_WIDTH = 32,
    parameter R_ADDR_WIDTH = 4  // ความจุ 16 ช่อง (32-bit)
    // หมายเหตุ: W_DATA_WIDTH * 2^W_ADDR_WIDTH ต้องเท่ากับ R_DATA_WIDTH * 2^R_ADDR_WIDTH เสมอ (512 bits)
)(
    input  logic wclk,
    input  logic wrst_n,
    input  logic w_en,
    input  logic [W_DATA_WIDTH-1:0] wdata,
    output logic wfull,
    
    input  logic rclk,
    input  logic rrst_n,
    input  logic r_en,
    output logic [R_DATA_WIDTH-1:0] rdata,
    output logic rempty
);

    // =================================================================
    // 1. ตัวแปรและ Pointers (สเกลใครสเกลมัน)
    // =================================================================
    logic [W_ADDR_WIDTH-1:0] waddr;
    logic [W_ADDR_WIDTH:0]   wptr_g, wptr_bin;
    logic [W_ADDR_WIDTH:0]   wptr_g_sync, wptr_bin_sync; // จาก W ไป R

    logic [R_ADDR_WIDTH-1:0] raddr;
    logic [R_ADDR_WIDTH:0]   rptr_g, rptr_bin;
    logic [R_ADDR_WIDTH:0]   rptr_g_sync, rptr_bin_sync; // จาก R ไป W

    // =================================================================
    // 2. RAM แบบไม่สมมาตร (Asymmetric RAM Inference)
    // =================================================================
    // สร้าง RAM เป็น Array ตามขนาดของพอร์ตที่ "เล็กที่สุด" (ในที่นี้คือ 8-bit)
    logic [W_DATA_WIDTH-1:0] mem [0:(1<<W_ADDR_WIDTH)-1];

    // ฝั่งเขียน (8-bit): เขียนลงไปตรงๆ ช่องใครช่องมัน
    always_ff @(posedge wclk) begin
        if (w_en && !wfull) begin
            mem[waddr] <= wdata;
        end
    end

    // ฝั่งอ่าน (32-bit): ดึงทีเดียว 4 ช่องติดกันมาต่อกัน (Concatenation)
    // ใช้ Little-Endian: แอดเดรสต่ำอยู่ขวาสุด (LSB)
    always_ff @(posedge rclk) begin
        if (r_en && !rempty) begin
            rdata <= {
                mem[{raddr, 2'b11}], // Byte 3
                mem[{raddr, 2'b10}], // Byte 2
                mem[{raddr, 2'b01}], // Byte 1
                mem[{raddr, 2'b00}]  // Byte 0
            };
        end
    end

    // =================================================================
    // 3. Gray Counters (นับทีละ 1 อย่างปลอดภัย)
    // =================================================================
    gray_counter #(W_ADDR_WIDTH) w_cnt (
        .clk(wclk), .rst(!wrst_n), .en(w_en && !wfull), .ptr_g(wptr_g), .addr(waddr)
    );
    
    gray_counter #(R_ADDR_WIDTH) r_cnt (
        .clk(rclk), .rst(!rrst_n), .en(r_en && !rempty), .ptr_g(rptr_g), .addr(raddr)
    );

    // =================================================================
    // 4. Synchronizers
    // =================================================================
    sync_2stage #(W_ADDR_WIDTH+1) sync_w2r (
        .clk(rclk), .rst(!rrst_n), .d(wptr_g), .q(wptr_g_sync)
    );
    
    sync_2stage #(R_ADDR_WIDTH+1) sync_r2w (
        .clk(wclk), .rst(!wrst_n), .d(rptr_g), .q(rptr_g_sync)
    );

    // =================================================================
    // 5. Shift Alignment Logic (เวทมนตร์อยู่ตรงนี้!)
    // =================================================================
    
    // --- ฝั่ง Write (wclk) คำนวณความเต็ม (wfull) ---
    always_comb begin
        // 1. แปลง Gray เป็น Binary
        wptr_bin[W_ADDR_WIDTH] = wptr_g[W_ADDR_WIDTH];
        for (int i = W_ADDR_WIDTH-1; i >= 0; i--) wptr_bin[i] = wptr_bin[i+1] ^ wptr_g[i];

        rptr_bin_sync[R_ADDR_WIDTH] = rptr_g_sync[R_ADDR_WIDTH];
        for (int i = R_ADDR_WIDTH-1; i >= 0; i--) rptr_bin_sync[i] = rptr_bin_sync[i+1] ^ rptr_g_sync[i];
    end

    // *เคล็ดลับ:* เอา Read Pointer (สเกล 32-bit) มาคูณ 4 ให้กลายเป็นสเกล 8-bit
    // การคูณ 4 ในทางดิจิทัลคือการเติม 00 ต่อท้าย (Shift Left 2 บิต)
    logic [W_ADDR_WIDTH:0] rptr_scaled_to_w;
    assign rptr_scaled_to_w = {rptr_bin_sync, 2'b00};

    logic [W_ADDR_WIDTH:0] w_level;
    assign w_level = wptr_bin - rptr_scaled_to_w;
    assign wfull = (w_level >= (1 << W_ADDR_WIDTH));


    // --- ฝั่ง Read (rclk) คำนวณความว่าง (rempty) ---
    always_comb begin
        // 1. แปลง Gray เป็น Binary
        rptr_bin[R_ADDR_WIDTH] = rptr_g[R_ADDR_WIDTH];
        for (int i = R_ADDR_WIDTH-1; i >= 0; i--) rptr_bin[i] = rptr_bin[i+1] ^ rptr_g[i];

        wptr_bin_sync[W_ADDR_WIDTH] = wptr_g_sync[W_ADDR_WIDTH];
        for (int i = W_ADDR_WIDTH-1; i >= 0; i--) wptr_bin_sync[i] = wptr_bin_sync[i+1] ^ wptr_g_sync[i];
    end

    // *เคล็ดลับ:* เอา Write Pointer (สเกล 8-bit) มาหาร 4 ให้กลายเป็นสเกล 32-bit
    // การหาร 4 ในทางดิจิทัลคือการตัด 2 บิตล่างทิ้ง (Shift Right 2 บิต)
    logic [R_ADDR_WIDTH:0] wptr_scaled_to_r;
    assign wptr_scaled_to_r = wptr_bin_sync[W_ADDR_WIDTH : 2]; // ตัดเศษทิ้ง!

    logic [R_ADDR_WIDTH:0] r_level;
    assign r_level = wptr_scaled_to_r - rptr_bin;
    assign rempty = (r_level == 0);

endmodule
