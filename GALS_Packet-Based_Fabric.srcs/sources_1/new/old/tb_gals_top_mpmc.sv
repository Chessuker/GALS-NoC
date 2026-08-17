`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: Thawat Boonsuk
// 
// Create Date: 06/04/2026 04:53:32 PM
// Design Name: 
// Module Name: tb_gals_top_mpmc
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

`include "transaction.svh"  
`include "scoreboard.svh"
`include "coverage_collector.svh"


module tb_gals_top_mpmc;
    
    // ==========================================
    // 1. สัญญาณ Clocks & Resets
    // ==========================================
    logic clk_P0 = 0, clk_P1 = 0, clk_P2 = 0, clk_B = 0;
    logic rst_P0_n, rst_P1_n, rst_P2_n, rst_B_n;
    logic [2:0] p_ecc_single;
    logic [2:0] p_ecc_double;

    always #4  clk_P0 = ~clk_P0; // 125 MHz
    always #5  clk_P1 = ~clk_P1; // 100 MHz
    always #6  clk_P2 = ~clk_P2; // 83.3 MHz
    always #3  clk_B  = ~clk_B;  // 166 MHz (Fast Consumer)

    // ==========================================
    // 2. สัญญาณเชื่อมต่อ DUT
    // ==========================================
    logic p0_valid = 0, p1_valid = 0, p2_valid = 0;
    logic [7:0] p0_data, p1_data, p2_data;
    logic p0_full, p1_full, p2_full;

    logic consumer_ready = 1;
    logic consumer_valid;
    logic [7:0] consumer_data;

    // ตัวแปรคุมการจบ Simulation (ป้องกัน Deadlock)
    logic test_done = 0;

    // Instance ของ IP ที่เราออกแบบ
    gals_top_mpmc #()dut (
        .clk_P0(clk_P0), .rst_P0_n(rst_P0_n), .p0_valid(p0_valid), .p0_data(p0_data), .p0_full(p0_full),
        .clk_P1(clk_P1), .rst_P1_n(rst_P1_n), .p1_valid(p1_valid), .p1_data(p1_data), .p1_full(p1_full),
        .clk_P2(clk_P2), .rst_P2_n(rst_P2_n), .p2_valid(p2_valid), .p2_data(p2_data), .p2_full(p2_full),
        .clk_B(clk_B),   .rst_B_n(rst_B_n),   
        .consumer_ready(consumer_ready), .consumer_valid(consumer_valid), .consumer_data(consumer_data),
        .p_ecc_single_err (p_ecc_single), .p_ecc_double_err (p_ecc_double)
    );

    // ==========================================
    // 3. Test Flow
    // ==========================================
    Scoreboard scb;
    CoverageCollector cov;

    initial begin
        scb = new();
        cov = new();
        
        // Assert Resets
        rst_P0_n = 0; rst_P1_n = 0; rst_P2_n = 0; rst_B_n = 0;
        #50;
        rst_P0_n = 1; rst_P1_n = 1; rst_P2_n = 1; rst_B_n = 1;
        #50;

        $display("--- Starting Constrained-Random Testing ---");

        // =======================================================
        // BACKGROUND THREADS (ทำงานขนานไปเรื่อยๆ จนกว่าจะ test_done)
        // =======================================================
        fork
            // กล้องวงจรปิด Coverage
            while(!test_done) begin @(posedge clk_P0); cov.sample_data(0, p0_full, consumer_ready, p_ecc_single, p_ecc_double); end
            while(!test_done) begin @(posedge clk_P1); cov.sample_data(1, p1_full, consumer_ready, p_ecc_single, p_ecc_double); end
            while(!test_done) begin @(posedge clk_P2); cov.sample_data(2, p2_full, consumer_ready, p_ecc_single, p_ecc_double); end

            // Thread 4: Consumer สุ่มดึงข้อมูล (ปรับ ready 60%)
            begin
                while(!test_done) begin
                    @(negedge clk_B);
                    consumer_ready <= ($urandom_range(0, 100) < 60); 
                end
            end

            // Thread 5: Monitor ดักจับผลลัพธ์ไปส่ง Scoreboard
            begin
                while(!test_done) begin
                    @(posedge clk_B);
                    #1
                    if (consumer_valid && consumer_ready) begin
                        scb.check_actual(consumer_data);
                    end
                end
            end
        join_none // <--- วิ่งเบื้องหลัง ไม่บล็อกโค้ดหลัก

        // =======================================================
        // FOREGROUND THREADS (Producer แข่งกันยัดข้อมูล)
        // =======================================================
        fork
            // Thread 1: P0
            begin
                Transaction tr;
                for (int i=0; i<100; i++) begin
                    tr = new();
                    assert(tr.randomize());
                    tr.producer_id = 0;
                    
                    @(negedge clk_P0);
                    while (p0_full) @(negedge clk_P0);
                    
                    p0_data  <= {tr.producer_id, tr.payload};
                    p0_valid <= 1;
                    
                    @(posedge clk_P0);
                    #1;
                    if (!p0_full) scb.write_expected(tr);
                    
                    @(negedge clk_P0);
                    p0_valid <= 0;
                    repeat(tr.delay_cycles) @(negedge clk_P0);
                end
            end
            
            // Thread 2: P1
            begin
                Transaction tr;
                for (int i=0; i<100; i++) begin
                    tr = new();
                    assert(tr.randomize());
                    tr.producer_id = 1;
                    
                    @(negedge clk_P1);
                    while (p1_full) @(negedge clk_P1);
                    
                    p1_valid <= 1;
                    p1_data  <= {tr.producer_id, tr.payload};
                    
                    @(posedge clk_P1);
                    #1;
                    if (!p1_full) scb.write_expected(tr);
                    
                    @(negedge clk_P1);
                    p1_valid <= 0;
                    repeat(tr.delay_cycles) @(negedge clk_P1); // แก้เป็น negedge แล้ว
                end
            end

            // Thread 3: P2
            begin
                Transaction tr;
                for (int i=0; i<100; i++) begin
                    tr = new();
                    assert(tr.randomize());
                    tr.producer_id = 2;
                    
                    @(negedge clk_P2);
                    while (p2_full) @(negedge clk_P2);
                    
                    p2_valid <= 1;
                    p2_data  <= {tr.producer_id, tr.payload};
                    
                    @(posedge clk_P2);
                    #1;
                    if (!p2_full) scb.write_expected(tr);
                    
                    @(negedge clk_P2);
                    p2_valid <= 0;
                    repeat(tr.delay_cycles) @(negedge clk_P2); // แก้เป็น negedge แล้ว
                end
            end
        join // <--- รอให้ P0, P1, P2 ส่งข้อมูลให้ครบ 100 ตัวทั้งหมดถึงจะไปต่อ

        // =======================================================
        // CLEANUP & DRAIN (ล้างท่อ)
        // =======================================================
        $display("All producers finished. Waiting for consumer to drain the FIFO...");
        
        // ให้เวลา Consumer 500 clock เพื่อดูดของที่ตกค้างใน FIFO ออกมาให้หมด
        repeat(500) @(posedge clk_B);
        
        // เช็คว่ามีข้อมูลตกค้างไหม (เรียกฟังก์ชันที่เราเพิ่งเพิ่มใน Scoreboard)
        scb.check_drain();

        // ปิดการทำงาน Background Threads
        test_done = 1;
        #100;
        
        // =======================================================
        // REPORT SUMMARY
        // =======================================================
        $display("--- Summary ---");
        $display("Number of data items that passed testing: %0d", scb.match_cnt);
        $display("Number of errors: %0d", scb.errors);
        
        cov.report();
        
        if (scb.errors == 0) $display("=== TEST PASSED! ===");
        else                 $display("=== TEST FAILED! ===");
        
        $finish;
    end
endmodule
