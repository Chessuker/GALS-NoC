`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/02/2026 02:51:55 PM
// Design Name: 
// Module Name: gals_node_wrapper
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


module gals_node_wrapper #(
    parameter DATA_W = 8,
    parameter CORD_W = 2,
    parameter DEPTH = 16,
    parameter NUM_VCS = 2
)(
    input  logic rst_n,

    input  logic clk_host,
    input  logic              s_host_valid,
    input  logic              s_host_tlast,
    input  logic [3:0]        s_host_tdest,
    input  logic [DATA_W-1:0] s_host_tdata,
    input  logic [NUM_VCS-1:0]s_host_tid,
    output logic [NUM_VCS-1:0]s_host_ready,
    
    output logic              m_host_valid,
    output logic              m_host_tlast,
    output logic [3:0]        m_host_tdest,
    output logic [DATA_W-1:0] m_host_tdata,
    output logic [NUM_VCS-1:0]m_host_tid,
    input  logic [NUM_VCS-1:0]m_host_ready,

    input  logic clk_noc,
    output logic              m_noc_valid,
    output logic              m_noc_tlast,
    output logic [3:0]        m_noc_tdest,
    output logic [DATA_W-1:0] m_noc_tdata,
    output logic [NUM_VCS-1:0]m_noc_tid,
    input  logic [NUM_VCS-1:0]m_noc_ready,
    
    input  logic              s_noc_valid,
    input  logic              s_noc_tlast,
    input  logic [3:0]        s_noc_tdest,
    input  logic [DATA_W-1:0] s_noc_tdata,
    input  logic [NUM_VCS-1:0]s_noc_tid,
    output logic [NUM_VCS-1:0]s_noc_ready
);

    localparam PACK_W = 1 + 4 + DATA_W; 
    localparam ADDR_W = $clog2(DEPTH);

    // =========================================================
    // Path 1: Host -> NoC
    // =========================================================
    logic [PACK_W-1:0] tx_wdata, tx_rdata [NUM_VCS];
    logic tx_empty [NUM_VCS], tx_full [NUM_VCS];
    assign tx_wdata = {s_host_tlast, s_host_tdest, s_host_tdata};

    genvar v;
    generate
        for (v = 0; v < NUM_VCS; v++) begin : TX_VC
            async_fifo_fwft #(.DATA_WIDTH(PACK_W), .ADDR_WIDTH(ADDR_W)) tx_fifo (
                .wclk(clk_host), .wrst_n(rst_n),
                .w_en(s_host_valid && s_host_tid[v] && !tx_full[v]),
                .wdata(tx_wdata), .wfull(tx_full[v]),
                
                .rclk(clk_noc),  .rrst_n(rst_n), 
                .r_en(m_noc_valid && m_noc_tid[v] && m_noc_ready[v]), 
                .rdata(tx_rdata[v]), .rempty(tx_empty[v]),            
                
                .almost_full(), .prog_full_thresh('0), .ecc_single_err(), .ecc_double_err()
            );
            assign s_host_ready[v] = ~tx_full[v];
        end
    endgenerate

    // 🏎️ Flit-by-Flit Interleaving MUX (ไม่มีการล็อคคิว!)
    always_comb begin
        m_noc_valid = 1'b0; m_noc_tid = '0; m_noc_tlast = 1'b0; m_noc_tdest = '0; m_noc_tdata = '0;
        
        // เลือกว่าจะ "เสนอ" ข้อมูลจาก VC ไหน โดยไม่ดู ready เลย
        if (!tx_empty[1]) begin 
            m_noc_valid = 1'b1; m_noc_tid = 2'b10;
            {m_noc_tlast, m_noc_tdest, m_noc_tdata} = tx_rdata[1];
        end else if (!tx_empty[0]) begin
            m_noc_valid = 1'b1; m_noc_tid = 2'b01;
            {m_noc_tlast, m_noc_tdest, m_noc_tdata} = tx_rdata[0];
        end
    end

    // =========================================================
    // Path 2: NoC -> Host
    // =========================================================
    logic [PACK_W-1:0] rx_wdata, rx_rdata [NUM_VCS];
    logic rx_empty [NUM_VCS], rx_full [NUM_VCS];
    assign rx_wdata = {s_noc_tlast, s_noc_tdest, s_noc_tdata};

    generate
        for (v = 0; v < NUM_VCS; v++) begin : RX_VC
            async_fifo_fwft #(.DATA_WIDTH(PACK_W), .ADDR_WIDTH(ADDR_W)) rx_fifo (
                .wclk(clk_noc), .wrst_n(rst_n),
                .w_en(s_noc_valid && s_noc_tid[v] && !rx_full[v]),
                .wdata(rx_wdata), .wfull(rx_full[v]),
                
                .rclk(clk_host), .rrst_n(rst_n), 
                .r_en(m_host_valid && m_host_tid[v] && m_host_ready[v]),
                .rdata(rx_rdata[v]), .rempty(rx_empty[v]),            
                
                .almost_full(), .prog_full_thresh('0), .ecc_single_err(), .ecc_double_err()
            );
            assign s_noc_ready[v] = ~rx_full[v];
        end
    endgenerate

    // 🏎️ Flit-by-Flit Interleaving MUX (ให้ Host รับไปประกอบเอง)
    always_comb begin
        m_host_valid = 1'b0; m_host_tid = '0; m_host_tlast = 1'b0; m_host_tdest = '0; m_host_tdata = '0;
        
        if (!rx_empty[1]) begin
            m_host_valid = 1'b1; m_host_tid = 2'b10;
            {m_host_tlast, m_host_tdest, m_host_tdata} = rx_rdata[1];
        end else if (!rx_empty[0]) begin
            m_host_valid = 1'b1; m_host_tid = 2'b01;
            {m_host_tlast, m_host_tdest, m_host_tdata} = rx_rdata[0];
        end
    end

endmodule

