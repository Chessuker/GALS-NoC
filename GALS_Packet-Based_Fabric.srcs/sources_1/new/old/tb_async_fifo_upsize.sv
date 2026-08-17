`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/04/2026 08:43:03 PM
// Design Name: 
// Module Name: tb_async_fifo_upsize
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


module tb_async_fifo_upsize;

    // ==========================================
    // 1. กำหนดสัญญาณ (Signals)
    // ==========================================
    parameter W_DATA_WIDTH = 8;
    parameter W_ADDR_WIDTH = 6; // 64 ช่อง (8-bit)
    parameter R_DATA_WIDTH = 32;
    parameter R_ADDR_WIDTH = 4; // 16 ช่อง (32-bit)

    logic wclk = 0, rclk = 0;
    logic wrst_n, rrst_n;
    
    // พอร์ต Write
    logic w_en = 0;
    logic [W_DATA_WIDTH-1:0] wdata = 0;
    logic wfull;
    
    // พอร์ต Read
    logic r_en = 0;
    logic [R_DATA_WIDTH-1:0] rdata;
    logic rempty;

    // สร้าง Clocks
    always #5  wclk = ~wclk; // 100 MHz
    always #13 rclk = ~rclk; // ~38.4 MHz (อ่านช้ากว่าเขียน)

    // ==========================================
    // 2. เรียกใช้ Device Under Test (DUT)
    // ==========================================
    async_fifo_upsize #(
        .W_DATA_WIDTH(W_DATA_WIDTH), .W_ADDR_WIDTH(W_ADDR_WIDTH),
        .R_DATA_WIDTH(R_DATA_WIDTH), .R_ADDR_WIDTH(R_ADDR_WIDTH)
    ) dut (
        .wclk(wclk), .wrst_n(wrst_n), .w_en(w_en), .wdata(wdata), .wfull(wfull),
        .rclk(rclk), .rrst_n(rrst_n), .r_en(r_en), .rdata(rdata), .rempty(rempty)
    );

    // ==========================================
    // 3. Scoreboard (คิวเฉลย) และตัวแปรนับ
    // ==========================================
    logic [R_DATA_WIDTH-1:0] expected_q[$];
    int match_cnt = 0;
    int error_cnt = 0;

    // ==========================================
    // 4. Test Scenario (การทดสอบ)
    // ==========================================
    initial begin
        // --- 4.1 Reset ระบบ ---
        wrst_n = 0; rrst_n = 0;
        #50;
        wrst_n = 1; rrst_n = 1;
        #50;

        $display("=== Starting Upsize FIFO Test (8-bit to 32-bit) ===");

        fork
            // ---------------------------------------------------------
            // Thread 1: ฝั่งเขียน (อัดข้อมูลทีละ 8 บิต 400 ครั้ง = 100 Word)
            // ---------------------------------------------------------
            begin
                logic [7:0] byte_array[4]; // เปลี่ยนมาใช้ Array ธรรมดา
                logic [R_DATA_WIDTH-1:0] expected_word;

                for (int i = 0; i < 100; i++) begin
                    // 1. สุ่มค่า 4 ไบต์ใส่ Array
                    for (int j = 0; j < 4; j++) begin
                        byte_array[j] = $urandom();
                    end
                    
                    // 2. ประกอบร่างคำตอบที่ถูกต้อง (Little Endian: ไบต์ 0 อยู่ LSB)
                    expected_word = {byte_array[3], byte_array[2], byte_array[1], byte_array[0]};
                    expected_q.push_back(expected_word);

                    // 3. ยิงข้อมูล 4 ครั้ง
                    for (int idx = 0; idx < 4; idx++) begin
                        @(posedge wclk); #1;
                        while (wfull) begin @(posedge wclk); #1; end // รอถ้าเต็ม
                        
                        w_en  <= 1;
                        wdata <= byte_array[idx]; // ดึงค่าจาก Array มาใช้ตรงๆ เลย
                    end
                    
                    @(posedge wclk); #1;
                    w_en <= 0; // พักการส่ง
                    
                    // สุ่มการหยุดพัก
                    repeat($urandom_range(0, 5)) @(posedge wclk);
                end
            end

            // ---------------------------------------------------------
            // Thread 2: ฝั่งอ่าน (ดึงข้อมูลทีละ 32 บิต ออกมาตรวจ)
            // ---------------------------------------------------------
            begin
                logic [R_DATA_WIDTH-1:0] exp_val;
                
                // รอจนกว่าจะอ่านครบ 100 คำ
                while (match_cnt + error_cnt < 100) begin
                    @(posedge rclk); #1;
                    
                    if (!rempty) begin
                        // 1. สั่ง r_en = 1 เพื่อเขยิบ Pointer และบอกให้ RAM คายข้อมูลออกมาก่อน
                        r_en <= 1;
                        @(posedge rclk); #1; // รอ 1 Clock ให้ข้อมูลอัปเดตมาที่พอร์ต rdata
                        
                        r_en <= 0; // ปิดสัญญาณอ่านเพื่อไม่ให้มันไหลเกิน
                        
                        // 2. ข้อมูลมาถึงแล้ว เอามาตรวจได้เลย
                        exp_val = expected_q.pop_front();
                        if (rdata !== exp_val) begin
                            $error("[%0t] ERROR! Expected=0x%0h, Read=0x%0h", $time, exp_val, rdata);
                            error_cnt++;
                        end else begin
                            match_cnt++;
                        end
                    end else begin
                        r_en <= 0;
                    end
                end
            end
        join

        // --- 4.3 สรุปผล ---
        $display("==================================================");
        $display("   Summary of Upsize FIFO Test");
        $display("   Correct 32-bit data read : %0d Words", match_cnt);
        $display("   Errors        : %0d", error_cnt);
        $display("==================================================");
        if (error_cnt == 0) $display("=== TEST PASSED! ===");
        else                $display("=== TEST FAILED! ===");
        
        $finish;
    end

endmodule