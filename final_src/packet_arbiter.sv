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
    parameter PORTS = 4
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
    logic             locked_from_mask; // จำว่าคิวนี้ได้มาจากการเข้าคิวปกติ (1) หรือลัดคิว (0)
    
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
                        end
                    end
                end

                LOCKED: begin
                    if (eop_transfer) begin
                        state            <= IDLE;
                        locked_grant     <= '0;
                        locked_from_mask <= 1'b0;
                    end
                end
            endcase

            // --- Persistent Round Robin Mask Update ---
            // อัปเดต Mask "เฉพาะ" เมื่อ:
            // 1. คนที่เพิ่งส่งเสร็จ เป็นเจ้าของคิวตัวจริง (current_from_mask)
            // 2. หรือ Mask ทะลุกลายเป็น 0000 ไปแล้ว (ต้องรีเซ็ต)
            if (eop_transfer) begin
                if (current_from_mask || mask == '0) begin
                    // แทนค่าสมการลงไปตรงๆ เพื่อเลี่ยงการประกาศตัวแปร automatic
                    mask <= (~(grant | (grant - 1'b1)) == '0) ? {PORTS{1'b1}} : ~(grant | (grant - 1'b1));
                end
            end            
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
                if ($past(state) == LOCKED && !$past(eop_transfer)) begin
                    assert_channel_lock: assert(grant == $past(grant));
                end
            end
        end
    `endif

endmodule
