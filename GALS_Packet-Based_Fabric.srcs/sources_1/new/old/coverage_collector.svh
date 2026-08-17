class CoverageCollector;

    // 1. เพิ่มตัวแปร ecc_single และ ecc_double เข้ามาใน function sample
    covergroup mpmc_cg with function sample(logic [1:0] pid, logic full_flag, logic ready_flag, logic [2:0] ecc_single, logic [2:0] ecc_double);
        option.per_instance = 1;
        option.name = "MPMC_Functional_Coverage";

        cp_producer: coverpoint pid {
            bins p0_active = {0}; bins p1_active = {1}; bins p2_active = {2};
        }

        cp_fifo_full: coverpoint full_flag {
            bins not_full = {0}; bins hit_full = {1};
        }

        cp_consumer_ready: coverpoint ready_flag {
            bins stall_traffic = {0}; bins ready_to_receive = {1};
        }

        // [แก้บั๊กที่ 1]: สร้าง Cross Coverage แบบ 3 มิติ (Producer x Full x Ready)
        cr_pid_x_full_x_ready: cross cp_producer, cp_fifo_full, cp_consumer_ready;

        // [แก้บั๊กที่ 2]: เพิ่ม Coverpoints สำหรับเก็บสถิติ ECC Errors
        cp_ecc_single: coverpoint ecc_single {
            bins no_error = {0};
            bins has_error = {[1:7]}; // ถ้ามีบิตไหนเป็น 1 ถือว่าเกิด Single Error
        }

        cp_ecc_double: coverpoint ecc_double {
            bins no_error = {0};
            bins has_error = {[1:7]}; // ถ้ามีบิตไหนเป็น 1 ถือว่าเกิด Double Error
        }
    endgroup

    function new();
        mpmc_cg = new();
    endfunction

    // อัปเดตฟังก์ชัน sample_data ให้รับค่า ECC
    // (ใส่ = 0 เป็น Default Argument ไว้ เพื่อไม่ให้ Testbench เก่าพังถ้าลืมส่งค่ามา)
    function void sample_data(logic [1:0] pid, logic full_flag, logic ready_flag, logic [2:0] ecc_single = 0, logic [2:0] ecc_double = 0);
        mpmc_cg.sample(pid, full_flag, ready_flag, ecc_single, ecc_double);
    endfunction

    function void report();
        $display("==================================================");
        $display("   Functional Coverage: %0.2f %%", mpmc_cg.get_inst_coverage());
        $display("==================================================");
    endfunction

endclass