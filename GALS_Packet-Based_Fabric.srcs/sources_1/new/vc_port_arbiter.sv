`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/03/2026 10:35:35 PM
// Design Name: 
// Module Name: vc_port_arbiter
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


// =====================================================================
// VC Port Arbiter (Strict Priority with Packet-Level Anti-Starvation)
// =====================================================================
module vc_port_arbiter #(
    parameter PORTS = 4,
    parameter int STARVE_LIMIT = 64
)(
    input  logic clk,
    input  logic rst_n,

    input  logic [PORTS-1:0] valid_vc1,
    input  logic [PORTS-1:0] tlast_vc1,
    output logic [PORTS-1:0] grant_vc1,

    input  logic [PORTS-1:0] valid_vc0,
    input  logic [PORTS-1:0] tlast_vc0,
    output logic [PORTS-1:0] grant_vc0,

    input  logic             ready_out_vc1,
    input  logic             ready_out_vc0,
    output logic             ready_vc1, 
    output logic             ready_vc0  
);

    logic [PORTS-1:0] raw_grant_vc1;
    logic [PORTS-1:0] raw_grant_vc0;

    packet_arbiter #(.PORTS(PORTS)) arb_vc1 (
        .clk(clk), .rst_n(rst_n),
        .valid(valid_vc1), .tlast(tlast_vc1), 
        .ready(ready_vc1), .grant(raw_grant_vc1)
    );

    packet_arbiter #(.PORTS(PORTS)) arb_vc0 (
        .clk(clk), .rst_n(rst_n),
        .valid(valid_vc0), .tlast(tlast_vc0), 
        .ready(ready_vc0), .grant(raw_grant_vc0)
    );

    // =================================================================
    // Anti-Starvation State Machine + DEBUG PROBES
    // =================================================================
    logic [7:0] starve_cnt;
    logic       vc0_override;
    logic       vc1_is_active;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            starve_cnt   <= '0;
            vc0_override <= 1'b0;
        end else begin
            // 🟢 โหมด Override (ให้สิทธิ์ VC0)
            if (vc0_override) begin
                if (|raw_grant_vc0 && ready_out_vc0 && |(tlast_vc0 & raw_grant_vc0)) begin
                    vc0_override <= 1'b0;
                    starve_cnt   <= '0;
`ifdef SIM_DEBUG
                    // 🔍 ปริ้นท์บอกตอนที่คืนถนนให้ VC1
                    $display("[%0t ns] [ARB DEBUG] %m finished VC0 Packet. Releasing Override.", $time);
`endif
                end
            end 
            // 🔴 โหมดปกติ (VC1 นำ)
            else begin
                if (|valid_vc0 && vc1_is_active) begin
                    // 🟢 แก้ให้หยุดนับทันทีเมื่อชน STARVE_LIMIT
                    if (starve_cnt < STARVE_LIMIT) starve_cnt <= starve_cnt + 1'b1; 
                end else if (!(|valid_vc0)) begin
                    starve_cnt <= '0; 
                end

                // ถ้าโกรธทะลุขีดจำกัด ให้เริ่มโหมด Override ทันที!
                if (starve_cnt >= STARVE_LIMIT) begin
                    vc0_override <= 1'b1;
`ifdef SIM_DEBUG
                    // 🔍 ปริ้นท์บอกตอนที่สั่งเบรก VC1 แบบ Cycle-Accurate!
                    $display("[%0t ns] [ARB DEBUG] %m Triggered VC0 Override! starve_cnt = %0d", $time, starve_cnt);
`endif
                end
            end
        end
    end

    assign vc1_is_active = |raw_grant_vc1 && !vc0_override; 

    // กั้นสัญญาณ
    assign grant_vc1 = vc1_is_active ? raw_grant_vc1 : '0;
    assign grant_vc0 = !vc1_is_active ? raw_grant_vc0 : '0;

    assign ready_vc1 = vc1_is_active ? ready_out_vc1 : 1'b0;
    assign ready_vc0 = !vc1_is_active ? ready_out_vc0 : 1'b0;

    // =================================================================
    // FORMAL VERIFICATION: Unified BMC, Prove, and Cover
    // =================================================================
    `ifdef FORMAL
        reg f_past_valid = 1'b0;
        always @(posedge clk) f_past_valid <= 1'b1;

        // -------------------------------------------------------------
        // 🟢 INVARIANTS: ตีกรอบความจริง ไม่ให้ Solver มโนสถานะประหลาด
        // -------------------------------------------------------------
        always @(*) begin
            if (rst_n && f_past_valid) begin
                if (raw_grant_vc1 != '0) assume($onehot(raw_grant_vc1));
                if (raw_grant_vc0 != '0) assume($onehot(raw_grant_vc0));
                
                // ตีกรอบความโกรธ (ห้ามทะลุเพดาน)
                assert_inv_starve_cap: assert(starve_cnt <= STARVE_LIMIT);
                
                // ผูกตัวนับ Formal ให้เดินไปพร้อมกับตัวนับ RTL เสมอ!
                if (!vc0_override) begin
                    assert_inv_wait_cap: assert(f_wait_cnt <= STARVE_LIMIT + 1);
                    if (starve_cnt < STARVE_LIMIT) begin
                        assert_inv_sync: assert(f_wait_cnt == starve_cnt);
                    end
                end
            end
        end

        // -------------------------------------------------------------
        // 🟢 SAFETY & LIVENESS: ตรวจสอบความถูกต้องของระบบ
        // -------------------------------------------------------------
        always @(posedge clk) begin
            if (f_past_valid && $past(rst_n) && rst_n) begin
                
                // SAFETY: ห้ามเกิดการ Override มั่วซั่ว ถ้ายังไม่ถึงลิมิต
                if (!$past(vc0_override) && vc0_override) begin
                    assert_override_only_at_limit: assert($past(starve_cnt) >= STARVE_LIMIT);
                end

                // SAFETY: ระหว่าง Override รถพยาบาลต้องหยุดวิ่งเด็ดขาด
                if (vc0_override) begin
                    assert_no_vc1_during_override: assert(!vc1_is_active);
                end

                // SAFETY: VC1 และ VC0 ต้องไม่ปล่อยไฟเขียวพร้อมกัน (ห้ามชนกัน)
                assert_vc_mutex: assert(!(|grant_vc1 && |grant_vc0));

                // LIVENESS: พิสูจน์ว่าถ้ารอจนเลยขีดจำกัด ต้องเกิดการ Override แน่นอน
                if (f_wait_cnt > (STARVE_LIMIT + 2)) begin
                    assert_bounded_starvation: assert(vc0_override || $past(vc0_override));
                end

                // -------------------------------------------------------------
                // 🟢 COVER PROPERTIES: พิสูจน์ว่าฟีเจอร์ทำงานได้จริง (Reachability)
                // -------------------------------------------------------------
                // 1. รถพยาบาลแทรกคิวสำเร็จ (อดีต VC0 วิ่ง, ปัจจุบัน VC1 แย่งไปวิ่ง)
                cover_vc1_preempts: cover($past(|grant_vc0) && !(|grant_vc0) && |grant_vc1);
                
                // 2. ป้าย Override ถูกชูขึ้น (เปลี่ยนจาก 0 เป็น 1)
                cover_override_activated: cover(!$past(vc0_override) && vc0_override);
                
                // 3. ปลดป้าย Override สำเร็จ (เปลี่ยนจาก 1 เป็น 0)
                cover_override_completed: cover($past(vc0_override) && !vc0_override);
            end
        end

        // ตัวนับ Formal (f_wait_cnt)
        logic [15:0] f_wait_cnt;
        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) begin
                f_wait_cnt <= '0;
            end else if (!(|valid_vc0)) begin
                f_wait_cnt <= '0;
            end else if (vc0_override && |grant_vc0 && ready_out_vc0 && |(tlast_vc0 & grant_vc0)) begin
                f_wait_cnt <= '0;
            end else if (|valid_vc0 && vc1_is_active && !vc0_override) begin
                f_wait_cnt <= f_wait_cnt + 1'b1;
            end
        end
    `endif

endmodule

