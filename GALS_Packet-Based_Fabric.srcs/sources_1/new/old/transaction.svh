class Transaction;
    logic [1:0] producer_id; // 0, 1, หรือ 2
    rand logic [5:0] payload;
    rand int         delay_cycles; // สุ่มจังหวะการหยุดส่งข้อมูล

    // ตั้งกฎการสุ่ม (Constraints)
    constraint c_delay { delay_cycles dist {0 := 95, [1:2] := 5}; }
//    constraint c_pid   { producer_id inside {0, 1, 2}; }

    // ฟังก์ชันช่วยแสดงผลตอน Debug
    function void display(string name);
        $display("[%0t] %s: Producer=%0d, Data=0x%0h", $time, name, producer_id, payload);
    endfunction
endclass