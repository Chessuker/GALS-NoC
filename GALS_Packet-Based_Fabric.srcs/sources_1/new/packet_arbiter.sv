`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/29/2026 11:26:11 PM
// Design Name: 
// Module Name: packet_arbiter
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


module packet_arbiter #(
    parameter PORTS = 4,
    // ---- timeout กันพอร์ตตายถาวรเมื่อต้นทางหายไปกลางแพ็กเกจ
    // นับเฉพาะไซเคิลที่ "ช่องที่ล็อกไว้ไม่มีข้อมูลเลย" (valid ตก)
    // ปลายทางบล็อก (ready=0) จะไม่ทำให้ตัวนับเดิน เพราะ valid ยังสูงอยู่
    // -> timeout นี้ไม่มีทางยิงเพราะ backpressure ยิงเฉพาะตอนต้นทางหายจริงๆ
    // ช่องว่างที่ถูกต้องตามกลไก GALS (FIFO แห้งชั่วคราว) อยู่ระดับสิบไซเคิล
    // 2^10 = 1024 จึงเผื่อไว้ ~100 เท่า
    parameter int STALL_LOG = 10
)(
    input  logic             clk,
    input  logic             rst_n,

    // AXI4-Stream Control Signals จากทุกพอร์ต
    input  logic [PORTS-1:0] valid,  // TVALID
    input  logic [PORTS-1:0] tlast,  // TLAST (บิตสำคัญที่ใช้ปลดล็อค)
    input  logic             ready,  // TREADY จากปลายทาง

    output logic [PORTS-1:0] grant   // สัญญาณเลือกช่อง (One-hot) ส่งให้ Mux
);

    typedef enum logic {IDLE, LOCKED} state_t;
    state_t state;

    logic [PORTS-1:0] locked_grant;
    logic [PORTS-1:0] mask; 

    // ---- ตัวนับ/สัญญาณของ timeout (ดูคำอธิบายที่ parameter STALL_LOG)
    localparam logic [STALL_LOG-1:0] STALL_MAX = {STALL_LOG{1'b1}};
    logic [STALL_LOG-1:0] stall_cnt;
    logic                 force_release;

    logic             locked_from_mask; // จำว่าคิวนี้ได้มาจากการเข้าคิวปกติ (1) หรือลัดคิว (0)
    logic             has_transferred;  // 🟢 เพิ่มใหม่: track ว่า locked_grant นี้ transfer สำเร็จไปแล้วอย่างน้อย 1 ครั้งไหม
    
    // -----------------------------------------------------------------
    // 1. ลอจิกหาคิวแบบ Round Robin (Combinational)
    // -----------------------------------------------------------------
    logic [PORTS-1:0] masked_req;
    logic [PORTS-1:0] masked_grant;
    logic [PORTS-1:0] unmasked_grant;
    logic [PORTS-1:0] next_grant;

    assign masked_req     = valid & mask;
    assign masked_grant   = masked_req & (~masked_req + 1'b1);
    assign unmasked_grant = valid & (~valid + 1'b1);
    
    assign next_grant     = (masked_req != '0) ? masked_grant : unmasked_grant;

    // -----------------------------------------------------------------
    // 2. เงื่อนไขการ "ส่งจบแพ็กเกจ" (End of Packet Transfer)
    // -----------------------------------------------------------------
    logic eop_transfer;
    assign eop_transfer = |(grant & valid & tlast) && ready;

    logic single_xfer;
    assign single_xfer = |(grant & valid) && ready; // transfer สำเร็จในไซเคิลนี้ (ไม่ต้องรอ tlast)

    // ปล่อยพอร์ตทิ้งเมื่อช่องที่ล็อกไว้เงียบนานเกินเกณฑ์ = ต้นทางหายไปแล้วจริง
    //
    // 🔴 ต้องมี !(|(locked_grant & valid)) ด้วย — formal จับได้ว่าขาดไม่ได้:
    //    stall_cnt เป็นรีจิสเตอร์ ถ้าต้นทางกลับมาส่งในไซเคิลเดียวกับที่ตัวนับ
    //    ชนเพดานพอดี จะเกิด force_release พร้อมกับที่มี flit จริงรออยู่
    //    = ปล่อยช่องกลางแพ็กเกจทั้งที่ของยังมา = bug #1 กลับมาเลย
    //    เงื่อนไขนี้ทำให้ "ต้นทางกลับมาทันเส้นตาย" ได้ล็อกต่อ ไม่ถูกตัดทิ้ง
    assign force_release = (state == LOCKED) && (stall_cnt == STALL_MAX)
                                            && !(|(locked_grant & valid));

    // -----------------------------------------------------------------
    // 3. สัญญาณ Output
    // -----------------------------------------------------------------
    assign grant = (state == LOCKED) ? locked_grant : (|valid ? next_grant : '0);

    logic current_from_mask;
    assign current_from_mask = (state == LOCKED) ? locked_from_mask : (masked_req != '0);

    // -----------------------------------------------------------------
    // 4. State Machine & Mask Update
    // -----------------------------------------------------------------
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= IDLE;
            locked_grant     <= '0;
            locked_from_mask <= 1'b0;
            has_transferred  <= 1'b0;
            stall_cnt        <= '0;
            mask             <= {PORTS{1'b1}}; 
        end else begin
            
            // --- State Transition (ล็อคแพ็กเกจ) ---
            case (state)
                IDLE: begin
                    if (|valid) begin
                        if (!(ready && |(next_grant & tlast))) begin
                            state            <= LOCKED;
                            locked_grant     <= next_grant;
                            locked_from_mask <= (masked_req != '0); // บันทึกไว้ว่าลัดคิวมาหรือไม่

                            // 🔴 จุดที่เคยพลาด: ตอน IDLE ตัว grant ก็ทำงานอยู่แล้ว
                            //    (ดู assign grant ด้านบน) ถ้าไซเคิลนี้ ready=1 และ valid=1
                            //    flit แรกของแพ็กเกจ "ออกไปแล้ว" พร้อมกับที่เรากำลังจะ lock
                            //    ถ้าตั้ง has_transferred <= 0 ตรงๆ ไซเคิลถัดไปที่ valid หลุด
                            //    (FIFO แห้ง ซึ่งเกิดประจำใน GALS) เงื่อนไขปลดล็อคฉุกเฉิน
                            //    จะเข้าใจผิดว่า "ยังไม่เคยส่งอะไรเลย" แล้วปล่อยพอร์ตกลางแพ็กเกจ
                            //    ทำให้แพ็กเกจจากอินพุตอื่นแทรกเข้ามาใน VC เดียวกัน
                            has_transferred  <= (ready && |(next_grant & valid));
                        end
                    end
                end

                LOCKED: begin
                    if (eop_transfer) begin
                        state            <= IDLE;
                        locked_grant     <= '0;
                        locked_from_mask <= 1'b0;
                        has_transferred  <= 1'b0;
                    end else if (single_xfer) begin
                        has_transferred  <= 1'b1;  // 🟢 มี transfer เกิดขึ้นแล้ว (แต่ไม่ใช่ tlast)
                    end else if (force_release) begin
                        // 🔴 BUG #5: ต้นทางหายไปกลางแพ็กเกจ (โหนดดับ/รีเซ็ต/ถูกตัด)
                        //    tlast ไม่มีวันมา -> eop_transfer ไม่เกิด
                        //    ปลดล็อคฉุกเฉินข้างล่างก็ยิงไม่ได้ เพราะ has_transferred=1
                        //    (เงื่อนไขนั้นใส่ไว้แก้ bug #1 นี่คือช่องที่มันเปิดทิ้งไว้)
                        //    ผล: พอร์ตนี้ตายถาวรจนกว่าจะรีเซ็ตทั้งระบบ
                        //    วัดจริง: ตัด agent_11 กลางแพ็กเกจตัวเดียว
                        //      -> agent_01 และ agent_10 ตายตามทั้งคู่ (gap ชนเพดาน)
                        //      = โหนดเดียวล้ม ทั้ง NoC ล้มตาม
                        //
                        //    ทิ้งแพ็กเกจกำพร้าดีกว่าให้พอร์ตตายถาวร
                        //    แพ็กเกจนั้นเสียอยู่แล้ว (ไม่มี tlast) และปลายทาง
                        //    จะเห็นเป็น sequence error ซึ่งรายงานได้อยู่แล้ว
                        state            <= IDLE;
                        locked_grant     <= '0;
                        locked_from_mask <= 1'b0;
                        has_transferred  <= 1'b0;
                    end else if (!has_transferred && !(|(locked_grant & valid))) begin
                        // 🟢 ปลดล็อคฉุกเฉินได้เฉพาะกรณี "ยังไม่เคย transfer เลยสักครั้ง" เท่านั้น
                        state            <= IDLE;
                        locked_grant     <= '0;
                        locked_from_mask <= 1'b0;
                    end
                end
            endcase

            // --- Persistent Round Robin Mask Update ---
            // เลื่อน mask ทุกครั้งที่ส่งจบแพ็กเกจ (round-robin มาตรฐาน)
            // 🔴 เดิมมีเงื่อนไข if (current_from_mask || mask == '0) ครอบอยู่
            //    เจตนาคือ "ถ้าชนะมาแบบลัดคิว อย่าเลื่อน mask ไปลงโทษเขา"
            //    แต่ผลจริงคือ starvation ถาวร:
            //      หลังพอร์ตสูงชนะ mask จะเลื่อนไปชี้พอร์ตที่ไม่มีใครขอ
            //      -> masked_req = 0 -> ตกไปใช้ unmasked_grant ซึ่งเลือกบิตต่ำสุดเสมอ
            //      -> current_from_mask = 0 -> mask ไม่ถูกอัปเดตอีกเลย
            //      -> พอร์ตหมายเลขต่ำสุดยึดช่องไว้ตลอดกาล
            //    round-robin ที่ถูกต้องต้องเลื่อน mask ทุกครั้งที่จบแพ็กเกจ
            //    (bug นี้ไม่โผล่ตอนทุกพอร์ตขอพร้อมกัน เพราะ mask มีคนขออยู่เสมอ
            //     จะเห็นก็ต่อเมื่อมีแค่บางพอร์ตแย่งกัน ซึ่งคือกรณีจริงทั้งหมด)
            if (eop_transfer) begin
                mask <= (~(grant | (grant - 1'b1)) == '0) ? {PORTS{1'b1}} : ~(grant | (grant - 1'b1));
            end            

            // --- ตัวนับ timeout: ล้างทุกครั้งที่ช่องที่ล็อกไว้ยังมีข้อมูลอยู่
            if (state != LOCKED)                stall_cnt <= '0;
            else if (|(locked_grant & valid))   stall_cnt <= '0;
            else if (stall_cnt != STALL_MAX)    stall_cnt <= stall_cnt + 1'b1;
        end
    end

    // =================================================================
    // FORMAL VERIFICATION: พิสูจน์ว่าช่องสัญญาณไม่มีทางถูกแย่งกลางคัน!
    // =================================================================
    `ifdef FORMAL
        reg f_past_valid = 1'b0;
        always @(posedge clk) f_past_valid <= 1'b1;

        // 1. บล็อกตรวจสอบสถานะปัจจุบัน (ไม่ต้องใช้คล็อก)
        always @(*) begin
            if (!f_past_valid) assume(!rst_n);
            if (rst_n && f_past_valid) begin
                if (grant != '0) begin
                    assert_onehot: assert($onehot(grant));
                end
            end
        end

        // 2. 🟢 ย้ายการตรวจสอบอดีต ($past) มาไว้ในบล็อกที่มีคล็อก 🟢
        always @(posedge clk) begin
            if (f_past_valid && $past(rst_n) && rst_n) begin
                // คุณสมบัติจริงที่ต้องการคือ "ห้ามแย่งช่องตราบใดที่ต้นทางยังส่งของอยู่"
                // เดิมเขียนแค่ !eop_transfer ซึ่ง *เป็นเท็จมาตลอด* และไม่มีใครรู้
                // เพราะไม่เคยมี .sby ชี้มาที่โมดูลนี้เลย (arbiter_formal.sby ชี้ผิดโมดูล)
                // ปลดล็อคฉุกเฉินเดิมก็เปลี่ยน grant กลางคัน LOCKED เหมือนกัน
                // ทางออกทั้งหมด (eop / ฉุกเฉิน / timeout) ต้องการให้ต้นทางเงียบก่อน
                // จึงตีกรอบด้วย "ต้นทางยังมีข้อมูลอยู่" ตรงๆ
                if ($past(state) == LOCKED && !$past(eop_transfer)
                                           && $past(|(locked_grant & valid))) begin
                    assert_channel_lock: assert(grant == $past(grant));
                end

                // timeout ต้องไม่ยิงเพราะ backpressure:
                // ถ้าช่องที่ล็อกไว้ยังมีข้อมูล ตัวนับต้องถูกล้างไปแล้ว
                if (force_release) begin
                    assert_abort_only_when_source_gone:
                        assert(!(|(locked_grant & valid)));
                end
            end
        end
    `endif

endmodule

