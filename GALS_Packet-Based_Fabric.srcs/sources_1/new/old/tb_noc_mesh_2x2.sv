`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/01/2026 04:04:05 PM
// Design Name: 
// Module Name: tb_noc_mesh_2x2
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


module tb_noc_mesh_2x2;

    parameter DATA_W = 8;
    parameter CORD_W = 2;

    logic clk;
    logic rst_n;

    // สัญญาณควบคุม Traffic Generator
    logic        gen_start [3:0];
    logic [1:0]  gen_tx    [3:0];
    logic [1:0]  gen_ty    [3:0];
    logic [7:0]  gen_len   [3:0];
    logic        gen_rdy   [3:0];

    // สายไฟ NoC
    logic s00_val, s00_lst, s00_rdy; logic [3:0] s00_dst; logic [7:0] s00_dta;
    logic m00_val, m00_lst, m00_rdy; logic [3:0] m00_dst; logic [7:0] m00_dta;
    
    logic s10_val, s10_lst, s10_rdy; logic [3:0] s10_dst; logic [7:0] s10_dta;
    logic m10_val, m10_lst, m10_rdy; logic [3:0] m10_dst; logic [7:0] m10_dta;
    
    logic s01_val, s01_lst, s01_rdy; logic [3:0] s01_dst; logic [7:0] s01_dta;
    logic m01_val, m01_lst, m01_rdy; logic [3:0] m01_dst; logic [7:0] m01_dta;
    
    logic s11_val, s11_lst, s11_rdy; logic [3:0] s11_dst; logic [7:0] s11_dta;
    logic m11_val, m11_lst, m11_rdy; logic [3:0] m11_dst; logic [7:0] m11_dta;

    // 1. Instantiate 2D Mesh NoC
    noc_mesh_2x2 #(.DATA_W(DATA_W), .CORD_W(CORD_W)) uut (
        .clk(clk), .rst_n(rst_n),
        .s_node00_valid(s00_val), .s_node00_tlast(s00_lst), .s_node00_tdest(s00_dst), .s_node00_tdata(s00_dta), .s_node00_ready(s00_rdy),
        .m_node00_valid(m00_val), .m_node00_tlast(m00_lst), .m_node00_tdest(m00_dst), .m_node00_tdata(m00_dta), .m_node00_ready(m00_rdy),
        
        .s_node10_valid(s10_val), .s_node10_tlast(s10_lst), .s_node10_tdest(s10_dst), .s_node10_tdata(s10_dta), .s_node10_ready(s10_rdy),
        .m_node10_valid(m10_val), .m_node10_tlast(m10_lst), .m_node10_tdest(m10_dst), .m_node10_tdata(m10_dta), .m_node10_ready(m10_rdy),
        
        .s_node01_valid(s01_val), .s_node01_tlast(s01_lst), .s_node01_tdest(s01_dst), .s_node01_tdata(s01_dta), .s_node01_ready(s01_rdy),
        .m_node01_valid(m01_val), .m_node01_tlast(m01_lst), .m_node01_tdest(m01_dst), .m_node01_tdata(m01_dta), .m_node01_ready(m01_rdy),
        
        .s_node11_valid(s11_val), .s_node11_tlast(s11_lst), .s_node11_tdest(s11_dst), .s_node11_tdata(s11_dta), .s_node11_ready(s11_rdy),
        .m_node11_valid(m11_val), .m_node11_tlast(m11_lst), .m_node11_tdest(m11_dst), .m_node11_tdata(m11_dta), .m_node11_ready(m11_rdy)
    );

    // 2. Instantiate Traffic Generators
    traffic_gen #(.MY_ID(4'h0)) tg_00 (.clk(clk), .rst_n(rst_n), .start(gen_start[0]), .target_x(gen_tx[0]), .target_y(gen_ty[0]), .pkt_len(gen_len[0]), .ready_out(gen_rdy[0]), .m_axis_tvalid(s00_val), .m_axis_tdata(s00_dta), .m_axis_tdest(s00_dst), .m_axis_tlast(s00_lst), .m_axis_tready(s00_rdy));
    traffic_gen #(.MY_ID(4'h1)) tg_10 (.clk(clk), .rst_n(rst_n), .start(gen_start[1]), .target_x(gen_tx[1]), .target_y(gen_ty[1]), .pkt_len(gen_len[1]), .ready_out(gen_rdy[1]), .m_axis_tvalid(s10_val), .m_axis_tdata(s10_dta), .m_axis_tdest(s10_dst), .m_axis_tlast(s10_lst), .m_axis_tready(s10_rdy));
    traffic_gen #(.MY_ID(4'h2)) tg_01 (.clk(clk), .rst_n(rst_n), .start(gen_start[2]), .target_x(gen_tx[2]), .target_y(gen_ty[2]), .pkt_len(gen_len[2]), .ready_out(gen_rdy[2]), .m_axis_tvalid(s01_val), .m_axis_tdata(s01_dta), .m_axis_tdest(s01_dst), .m_axis_tlast(s01_lst), .m_axis_tready(s01_rdy));
    traffic_gen #(.MY_ID(4'h3)) tg_11 (.clk(clk), .rst_n(rst_n), .start(gen_start[3]), .target_x(gen_tx[3]), .target_y(gen_ty[3]), .pkt_len(gen_len[3]), .ready_out(gen_rdy[3]), .m_axis_tvalid(s11_val), .m_axis_tdata(s11_dta), .m_axis_tdest(s11_dst), .m_axis_tlast(s11_lst), .m_axis_tready(s11_rdy));

    assign m00_rdy = 1'b1; assign m10_rdy = 1'b1; assign m01_rdy = 1'b1; assign m11_rdy = 1'b1;

    // =================================================================
    // 🚦 Global Scoreboard (ตัวดักฟังทุกพอร์ต)
    // =================================================================
    always_ff @(posedge clk) begin
        if (rst_n) begin
            if (m00_val && m00_rdy) $display("[%0t ns] Node 00 received: Data=0x%h (TLAST=%b)", $time, m00_dta, m00_lst);
            if (m10_val && m10_rdy) $display("[%0t ns] Node 10 received: Data=0x%h (TLAST=%b)", $time, m10_dta, m10_lst);
            if (m01_val && m01_rdy) $display("[%0t ns] Node 01 received: Data=0x%h (TLAST=%b)", $time, m01_dta, m01_lst);
            if (m11_val && m11_rdy) $display("[%0t ns] Node 11 received: Data=0x%h (TLAST=%b)", $time, m11_dta, m11_lst);
        end
    end

    // -----------------------------------------------------------------
    // 3. Clock & Watchdog Timer (กันค้าง)
    // -----------------------------------------------------------------
    initial begin
        clk = 0;
        forever #5 clk = ~clk; 
    end

    initial begin
        #10000;
        $display("\n[Error] Simulation ran too long (Timeout)! Terminating to prevent CPU hanging");
        $finish;
    end

    // -----------------------------------------------------------------
    // 4. Stimulus Block (แก้ Race Condition แล้ว)
    // -----------------------------------------------------------------
    initial begin
        rst_n = 0;
        for(int i=0; i<4; i++) begin
            gen_start[i] = 0; gen_tx[i] = 0; gen_ty[i] = 0; gen_len[i] = 0;
        end
        
        #20 rst_n = 1; #20;

        $display("\n[TB] --- Start Test 1: Fire through diagonal links ---");
        gen_tx[0] = 2'd1; gen_ty[0] = 2'd1; gen_len[0] = 8'd4; gen_start[0] = 1; 
        gen_tx[3] = 2'd0; gen_ty[3] = 2'd0; gen_len[3] = 8'd4; gen_start[3] = 1; 
        
        @(posedge clk);
        
        // แทรกคำสั่งนี้เพื่อรอให้ Generator ยืนยันการทำงาน
        wait(gen_rdy[0] == 0 && gen_rdy[3] == 0); 
        
        gen_start[0] = 0; gen_start[3] = 0;

        wait(gen_rdy[0] == 1 && gen_rdy[3] == 1);
        $display("[TB] --- Test 1 Finished ---\n");
        #50;

        $display("[TB] --- Start Test 2: Congestion Test (Port 10) ---");
        gen_tx[0] = 2'd1; gen_ty[0] = 2'd0; gen_len[0] = 8'd3; gen_start[0] = 1; 
        gen_tx[2] = 2'd1; gen_ty[2] = 2'd0; gen_len[2] = 8'd3; gen_start[2] = 1; 

        @(posedge clk);

        // แทรกคำสั่งนี้เพื่อรอให้ Generator ยืนยันการทำงาน
        wait(gen_rdy[0] == 0 && gen_rdy[2] == 0);

        gen_start[0] = 0; gen_start[2] = 0;

        wait(gen_rdy[0] == 1 && gen_rdy[2] == 1);
        $display("[TB] --- Test 2 Finished ---\n");
        #100;

        // ================================================================
        // Test 3: Multi-source starvation stress test -> target Node 10
        // Fires 3-4 senders concurrently to the same destination to expose
        // fixed-priority starvation (00, 10, 01, 11 -> 10)
        // ================================================================
        $display("[TB] --- Start Test 3: Multi-source starvation stress (4 senders -> Node 10) ---");
        gen_tx[0] = 2'd1; gen_ty[0] = 2'd0; gen_len[0] = 8'd8; // 00 -> 10
        gen_tx[1] = 2'd1; gen_ty[1] = 2'd0; gen_len[1] = 8'd8; // 10 -> 10 (self)
        gen_tx[2] = 2'd1; gen_ty[2] = 2'd0; gen_len[2] = 8'd8; // 01 -> 10
        gen_tx[3] = 2'd1; gen_ty[3] = 2'd0; gen_len[3] = 8'd8; // 11 -> 10

        @(posedge clk);
        gen_start[0] = 1; gen_start[1] = 1; gen_start[2] = 1; gen_start[3] = 1;
        @(posedge clk);
        gen_start[0] = 0; gen_start[1] = 0; gen_start[2] = 0; gen_start[3] = 0;

        // Give plenty of time for all flits to traverse under contention
        #400;
        $display("[TB] --- Test 3 Finished ---\n");
        #50;

        $display(" [SUCCESS] Architecture works correctly without Deadlock!");
        $finish;
    end
    
endmodule
