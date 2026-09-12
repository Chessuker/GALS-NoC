`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Module Name: fault_injector
//
// ตัวฉีดความผิดพลาดตอนรันจริง วางคั่นระหว่างขาส่งของ agent หนึ่งตัวกับ fabric
// ใช้พิสูจน์บนซิลิคอนว่าเกราะที่ใส่ไว้ (bug #5 timeout, bug #6 dest filter,
// tid guard, bug #7 force-close, constant-tdest guard) ทำงานจริงบนบอร์ด ไม่ใช่
// แค่ในซิม — ก่อนหน้านี้ทุก fault mode ของ tb_noc_stress_tester (KILL_MIDPKT,
// BAD_TID, BAD_DEST) ใช้ force ในซิมเท่านั้น
//
// ผลพลอยได้ที่จงใจ: พอ tdest/tid ของ agent ผ่าน mux ที่เลือกตอนรัน synthesis จะ
// พับตัวกรองปลายทางทิ้งไม่ได้อีก (ก่อนหน้านี้ dest_err ทั้งเส้นทางถูกตัดเป็นค่าคงที่
// ใน build stress เพราะ tdest เป็น parameter — ดู HANDOFF "Known gaps")
//
// จังหวะ: นับไซเคิลจากรีเซ็ต ถึง 2**FIRE_LOG แล้วรอ "กลางแพกเกจ" จริง (เห็น flit ที่
// ไม่ใช่ tlast ถูกรับไปแล้ว) จึงเริ่มฉีด — ตัดที่ขอบแพกเกจจะไม่เกิดอาการที่ต้องการ
// โหมด 1 ฉีดค้างถาวร โหมดอื่นฉีด HOLD ไซเคิลแล้วปล่อย (เหมือน force 2000 ไซเคิลในซิม)
//
// mode : 0 = ไม่ฉีด
//        1 = ตัด tvalid ถาวรกลางแพกเกจ      -> packet_arbiter ต้องปลดล็อกเอง (bug #5)
//        2 = tid = 00                        -> tid guard ทิ้ง+ยกธง, agent ค้าง (ถูกต้อง)
//        3 = tid = 11                        -> tid guard ทิ้ง+ยกธง, force-close
//        4 = tdest = 0001 (ในกระดาน ผิดโหนด) -> constant-tdest guard: dest_err + force-close
//        5 = tdest = 1000 (x=2 นอกกระดาน)    -> dest_ok filter (bug #6): dest_err, เมชไม่ตัน
//
// mode/arm มาจาก VIO (โดเมนอื่น) ผ่าน sync_2stage — ค่า static ก่อน arm จึงข้ามได้
//////////////////////////////////////////////////////////////////////////////////
module fault_injector #(
    parameter int FIRE_LOG = 20,     // ฉีดหลังรีเซ็ต 2**FIRE_LOG ไซเคิล (บอร์ด ~15 ms, ซิมตั้ง 12)
    parameter int HOLD     = 2000    // ไซเคิลที่ฉีดค้างสำหรับโหมด 2..5
)(
    input  logic       clk,
    input  logic       rst_n,
    input  logic [3:0] mode,
    input  logic       arm,

    // จาก agent
    input  logic [7:0] a_tdata,
    input  logic [3:0] a_tdest,
    input  logic [1:0] a_tid,
    input  logic       a_tlast,
    input  logic       a_tvalid,
    output logic [1:0] a_tready,

    // ไป fabric
    output logic [7:0] f_tdata,
    output logic [3:0] f_tdest,
    output logic [1:0] f_tid,
    output logic       f_tlast,
    output logic       f_tvalid,
    input  logic [1:0] f_tready,

    // สถานะ ให้ ILA ดู
    (* mark_debug = "true", dont_touch = "true" *) output logic        active,
    (* mark_debug = "true", dont_touch = "true" *) output logic        fired,   // เคยฉีดแล้ว (sticky)
    (* mark_debug = "true", dont_touch = "true" *) output logic [3:0]  mode_dbg
);
    logic [FIRE_LOG:0] cnt;
    logic              due;        // ถึงเวลาแล้ว รอกลางแพกเกจ
    logic [15:0]       hold_cnt;

    // flit ที่ถูกรับจริง (ดู tid ของ agent เอง ไม่ใช่ที่ฉีด — เหมือน tx_fire ใน agent)
    wire a_fire = a_tvalid && ((a_tid[0] && f_tready[0]) || (a_tid[1] && f_tready[1]));
    wire midpkt = a_fire && !a_tlast;

    assign mode_dbg = mode;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt      <= '0;
            due      <= 1'b0;
            active   <= 1'b0;
            fired    <= 1'b0;
            hold_cnt <= '0;
        end else begin
            if (!cnt[FIRE_LOG]) cnt <= cnt + 1'b1;
            if (arm && mode != '0 && cnt[FIRE_LOG] && !fired) due <= 1'b1;

            if (due && !active && midpkt) begin
                active   <= 1'b1;
                fired    <= 1'b1;
                due      <= 1'b0;
                hold_cnt <= '0;
            end else if (active && mode != 4'd1) begin
                if (hold_cnt == HOLD-1) active <= 1'b0;
                else                    hold_cnt <= hold_cnt + 1'b1;
            end
        end
    end

    // pass-through พร้อมทับค่าตามโหมด — ready ผ่านตรงเสมอ agent จึงเดินตามจังหวะปกติ
    // (ตรงกับที่ force ในซิมทำ: agent ใช้ tid ของตัวเองตัดสิน tx_fire)
    always_comb begin
        f_tdata  = a_tdata;
        f_tdest  = a_tdest;
        f_tid    = a_tid;
        f_tlast  = a_tlast;
        f_tvalid = a_tvalid;
        a_tready = f_tready;
        if (active) begin
            case (mode)
                4'd1: f_tvalid = 1'b0;
                4'd2: f_tid    = 2'b00;
                4'd3: f_tid    = 2'b11;
                4'd4: f_tdest  = 4'b0001;
                4'd5: f_tdest  = 4'b1000;
                default: ;
            endcase
        end
    end
endmodule
