`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/17/2026 05:13:18 PM
// Design Name: 
// Module Name: gals_mpmc_scalable
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


module gals_mpmc_scalable #(
    parameter NUM_PRODUCERS = 10,
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 12
)(
    input  logic [NUM_PRODUCERS-1:0]                   clk_P,      
    input  logic [NUM_PRODUCERS-1:0]                   rst_P_n,    
    input  logic [NUM_PRODUCERS-1:0]                   p_valid,    
    input  logic [NUM_PRODUCERS-1:0][DATA_WIDTH-1:0]   p_data, 
    output logic [NUM_PRODUCERS-1:0]                   p_full,     

    // ฝั่ง Consumer 
    input  logic                                       clk_C,
    input  logic                                       rst_C_n,
    input  logic                                       c_ready,
    output logic                                       c_valid,
    output logic [DATA_WIDTH-1:0]                      c_data,
    output logic [$clog2(NUM_PRODUCERS)-1:0]           c_source_id 
);

    logic [NUM_PRODUCERS-1:0]                 fifo_empty;
    logic [NUM_PRODUCERS-1:0]                 fifo_rd_en;
    logic [NUM_PRODUCERS-1:0][DATA_WIDTH-1:0] fifo_rdata;

    // ==========================================
    // 1. The FIFO Factory (ด่านรับข้อมูลข้ามคล็อก)
    // ==========================================
    genvar i;
    generate
        for (i = 0; i < NUM_PRODUCERS; i++) begin : gen_producer_fifos
            async_fifo #(
                .DATA_WIDTH(DATA_WIDTH),
                .ADDR_WIDTH(ADDR_WIDTH)
            ) fifo_inst (
                .wclk   (clk_P[i]),
                .wrst_n (rst_P_n[i]),
                .w_en   (p_valid[i] & ~p_full[i]),
                .wdata  (p_data[i]),
                .wfull  (p_full[i]),
                .w_level(),

                .rclk   (clk_C),
                .rrst_n (rst_C_n),
                .r_en   (fifo_rd_en[i]),
                .rdata  (fifo_rdata[i]),
                .rempty (fifo_empty[i]),
                
                .almost_full(),
                .prog_full_thresh({(ADDR_WIDTH+1){1'b0}}),
                .almost_empty(),
                .prog_empty_thresh({(ADDR_WIDTH+1){1'b0}}),
                .ecc_single_err(),
                .ecc_double_err()
            );
        end
    endgenerate
    
    // ==========================================
    // 2. Data Flattening (แปลง 2D Array เป็น 1D Array)
    // ==========================================
    logic [(NUM_PRODUCERS * DATA_WIDTH)-1:0] flat_fifo_rdata;
    generate
        for (i = 0; i < NUM_PRODUCERS; i++) begin : flatten_data
            assign flat_fifo_rdata[i * DATA_WIDTH +: DATA_WIDTH] = fifo_rdata[i];
        end
    endgenerate

    // ==========================================
    // 3. The Smart Arbiter (ฝัง hw_queue_descriptor)
    // ==========================================
    logic [NUM_PRODUCERS-1:0] grant_comb;
    logic                     valid_comb;
    logic [DATA_WIDTH-1:0]    data_comb;

    hw_queue_descriptor #(
        .NUM_PRODUCERS(NUM_PRODUCERS),
        .DATA_WIDTH(DATA_WIDTH)
    ) smart_arbiter (
        .clk        (clk_C),
        .rst_n      (rst_C_n),
        
        // 🔴 โยนสถานะคิวเข้าเป็น Request (~empty แปลว่ามีของขอส่ง)
        .req        (~fifo_empty),
        .grant      (grant_comb),
        
        .prod_data  (flat_fifo_rdata),
        
        // 🔴 ส่ง Backpressure จาก Consumer ย้อนกลับไปเบรก Arbiter
        .fifo_wfull (~c_ready),
        
        .fifo_w_en  (valid_comb),
        .fifo_wdata (data_comb)
    );

    // ==========================================
    // 4. One-Hot to Binary Encoder (หาหมายเลขห้องของข้อมูล)
    // ==========================================
    logic [$clog2(NUM_PRODUCERS)-1:0] source_id_comb;
    always_comb begin
        source_id_comb = '0;
        for (int k = 0; k < NUM_PRODUCERS; k++) begin
            if (grant_comb[k]) begin
                source_id_comb = k[$clog2(NUM_PRODUCERS)-1:0];
            end
        end
    end

    // ==========================================
    // 5. Output Registers (รักษา 1-Cycle Pipeline)
    // ==========================================
    
    assign fifo_rd_en = grant_comb;

    always_ff @(posedge clk_C or negedge rst_C_n) begin
        if (!rst_C_n) begin
            c_valid     <= 1'b0;
            c_data      <= '0;
            c_source_id <= '0;
        end else begin
            c_valid     <= valid_comb;
            c_data      <= data_comb;
            c_source_id <= source_id_comb;
        end
    end

endmodule
