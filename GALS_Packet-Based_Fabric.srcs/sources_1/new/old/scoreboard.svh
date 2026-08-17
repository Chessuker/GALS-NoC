class Scoreboard;
    // คิวเก็บข้อมูลที่คาดหวัง (Expected Queues) แยกตาม Producer
    bit [5:0] exp_q0[$];
    bit [5:0] exp_q1[$];
    bit [5:0] exp_q2[$];

    int errors = 0;
    int match_cnt = 0;

    // ฟังก์ชันรับข้อมูลฝั่งขาเข้า (จาก Generator/Monitor ขาเข้า)
    function void write_expected(Transaction tr);
        if (tr.producer_id == 0) exp_q0.push_back(tr.payload);
        else if (tr.producer_id == 1) exp_q1.push_back(tr.payload);
        else if (tr.producer_id == 2) exp_q2.push_back(tr.payload);
    endfunction

    // ฟังก์ชันตรวจคำตอบฝั่งขาออก (จาก Monitor ขาออก)
    function void check_actual(logic [7:0] actual_data);
        logic [1:0] act_pid = actual_data[7:6]; // สกัดป้ายชื่อ
        logic [5:0] act_pay = actual_data[5:0]; // สกัดข้อมูล
        logic [5:0] exp_pay;

        // ตรวจสอบว่ามีข้อมูลในคิวที่คาดหวังไหม
        if (act_pid == 0 && exp_q0.size() > 0) exp_pay = exp_q0.pop_front();
        else if (act_pid == 1 && exp_q1.size() > 0) exp_pay = exp_q1.pop_front();
        else if (act_pid == 2 && exp_q2.size() > 0) exp_pay = exp_q2.pop_front();
        else begin
            $error("[%0t] SCOREBOARD ERROR: Unexpected Data from Producer %0d!", $time, act_pid);
            errors++;
            return;
        end

        // ตรวจสอบความถูกต้อง
        if (act_pay !== exp_pay) begin
            $error("[%0t] SCOREBOARD ERROR: Data Mismatch! Expected=0x%0h, Actual=0x%0h", $time, exp_pay, act_pay);
            errors++;
        end else begin
            match_cnt++;
        end
    endfunction
    
    function void check_drain();
        if (exp_q0.size() > 0 || exp_q1.size() > 0 || exp_q2.size() > 0) begin
            $error("[%0t] SCOREBOARD FAIL: Items left in queue! Q0:%0d, Q1:%0d, Q2:%0d", 
                   $time, exp_q0.size(), exp_q1.size(), exp_q2.size());
            errors++;
        end else begin
            $display("[%0t] SCOREBOARD DRAIN OK: All queues are empty.", $time);
        end
    endfunction
endclass