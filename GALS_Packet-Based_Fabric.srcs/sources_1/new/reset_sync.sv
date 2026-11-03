`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: reset_sync
//
// รีเซ็ตต่อโดเมนนาฬิกา: assert แบบ asynchronous (กดปุ่มแล้วทุกอย่างหยุดทันที ไม่ต้อง
// มีคล็อก) แต่ deassert แบบ synchronous กับคล็อกของโดเมนนั้น ผ่าน 2 flop ASYNC_REG
//
// ทำไมต้องมี (2026-09-12): เดิม global_rst_n = ปุ่ม & pll_locked ตัวเดียว ต่อเข้า async
// reset ของ flop ทั้ง 5 โดเมน ขอบขาขึ้นของมันจึงมาถึง flop แต่ละตัวโดยไม่มีความสัมพันธ์
// กับคล็อกของ flop นั้น (recovery/removal ไม่ถูกตรวจ) report_cdc ไม่เคยฟ้องเพราะต้นทาง
// เป็นขาเข้าไม่มีคล็อก พอเพิ่ม soft reset จาก VIO (เป็น flop บน clk_h00) เข้าไปในสาย
// เดียวกัน report_cdc ฟ้อง CDC-7 Critical 572 เส้นทันที — ปัญหาเดิมที่เพิ่งมองเห็น
// ดีไซน์ทนได้มาตลอดเพราะทุก agent นอนใน S_WARMUP 1024 ไซเคิลก่อนส่งอะไร แต่นั่นคือโชค
// ไม่ใช่หลักประกัน
//
// srst (soft reset จาก VIO บนโดเมนอื่น) เข้าทางแยก: ไม่ AND เข้ากับ arst_n เพราะ
// report_cdc ฟ้อง CDC-10 (ลอจิกก่อน synchronizer บนขา CLR) และ glitch บน AND นั้น
// = รีเซ็ตทั้งโดเมนโดยไม่ตั้งใจ ทางแยกนี้ sync 2 flop ในโดเมนตัวเองแล้วค่อยกด rst_n
// แบบ synchronous — ช้ากว่าปุ่ม 2 ไซเคิล ไม่มีผลอะไร
//////////////////////////////////////////////////////////////////////////////////
module reset_sync (
    input  logic clk,
    input  logic arst_n,   // รีเซ็ตรวมจากขาที่ไม่มีคล็อก (ปุ่ม & pll_locked), asynchronous
    input  logic srst,     // soft reset active-high จากโดเมนอื่น (0 ถ้าไม่ใช้)
    output logic rst_n     // รีเซ็ตของโดเมนนี้: ตกทันทีตาม arst_n, ขึ้น/ลงตาม clk เมื่อมาจาก srst
);
    (* ASYNC_REG = "TRUE" *) logic q1, q2;
    (* ASYNC_REG = "TRUE" *) logic s1, s2;
    always_ff @(posedge clk or negedge arst_n) begin
        if (!arst_n) begin
            q1 <= 1'b0;
            q2 <= 1'b0;
            s1 <= 1'b1;
            s2 <= 1'b1;
        end else begin
            q1 <= 1'b1;
            q2 <= q1;
            s1 <= srst;
            s2 <= s1;
        end
    end
    assign rst_n = q2 & ~s2;
endmodule
