`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 04/07/2026 07:49:09 PM
// Design Name: 
// Module Name: dual_port_ram
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


module dual_port_ram #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
)(
    // clock_A
    input logic wclk,
    input logic w_en,
    input logic [ADDR_WIDTH-1:0] waddr,
    input logic [DATA_WIDTH-1:0] wdata,
    
    // clock_B
    input logic rclk,
    input logic r_en,
    input logic [ADDR_WIDTH-1:0] raddr,
    output logic [DATA_WIDTH-1:0] rdata
    );
    
    //depth of queue 2^ADDR_WIDTH
    localparam  DEPTH = 1 << ADDR_WIDTH;
    
    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];
    
    always_ff @(posedge wclk) begin
        if(w_en) begin 
            mem[waddr] <= wdata;
        end
    end
    
    always_ff @(posedge rclk) begin
        if(r_en) begin 
            rdata <= mem[raddr];
        end
    end 
endmodule

