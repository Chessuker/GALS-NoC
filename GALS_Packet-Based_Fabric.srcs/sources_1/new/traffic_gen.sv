`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/01/2026 03:54:17 PM
// Design Name: 
// Module Name: traffic_gen
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


module traffic_gen #(
    parameter [3:0] MY_ID = 4'h0,
    parameter NUM_VCS = 2
)(
    input  logic clk,
    input  logic rst_n,
    
    // ---------------------------------------------------------
    // Control Interface (รับคำสั่งจาก Testbench)
    // ---------------------------------------------------------
    input  logic start,
    input  logic [1:0] target_x,
    input  logic [1:0] target_y,
    input  logic [7:0] pkt_len,
    input  logic [NUM_VCS-1:0] pkt_tid, // VC ID ที่ต้องการส่ง (เช่น 2'b01 หรือ 2'b10)

    output logic ready_out,
    
    // ---------------------------------------------------------
    // AXI4-Stream Interface (ส่งออกสู่ Wrapper)
    // ---------------------------------------------------------
    output logic m_axis_tvalid,
    output logic [7:0] m_axis_tdata,
    output logic [3:0] m_axis_tdest,
    output logic m_axis_tlast,
    output logic [NUM_VCS-1:0] m_axis_tid, // สัญญาณบอกเลน
    input  logic [NUM_VCS-1:0] m_axis_tready // Ready ขาเข้าแยกตาม VC
);

    typedef enum logic [1:0] {IDLE, SEND} state_t;
    state_t state, next_state;

    logic [7:0] flit_cnt, next_flit_cnt;
    logic [7:0] data_reg, next_data_reg;
    
    // Latch ตัวแปรตอนสั่ง start
    logic [1:0] latch_tx, latch_ty;
    logic [7:0] latch_len;
    logic [NUM_VCS-1:0] latch_tid;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= IDLE;
            flit_cnt  <= '0;
            data_reg  <= {MY_ID, 4'h0};
            latch_tx  <= '0;
            latch_ty  <= '0;
            latch_len <= '0;
            latch_tid <= '0;
        end else begin
            state    <= next_state;
            flit_cnt <= next_flit_cnt;
            data_reg <= next_data_reg;
            
            if (state == IDLE && start) begin
                latch_tx  <= target_x;
                latch_ty  <= target_y;
                latch_len <= pkt_len;
                latch_tid <= pkt_tid; // จำบัตรคิว VC ไว้
            end
        end
    end

    // ตรวจสอบว่า "เลนที่เรากำลังจะส่ง" ปลายทางพร้อมรับหรือไม่?
    logic current_vc_ready;
    assign current_vc_ready = |(m_axis_tid & m_axis_tready);

    always_comb begin
        next_state    = state;
        next_flit_cnt = flit_cnt;
        next_data_reg = data_reg;
        
        m_axis_tvalid = 1'b0;
        m_axis_tlast  = 1'b0;
        
        ready_out = (state == IDLE);

        case (state)
            IDLE: begin
                if (start) begin
                    next_state = SEND;
                    next_flit_cnt = '0;
                    next_data_reg = {MY_ID, 4'h0};
                end
            end
            
            SEND: begin
                m_axis_tvalid = 1'b1;
                m_axis_tlast  = (flit_cnt == latch_len - 1);
                
                if (current_vc_ready) begin // เช็ค Ready เฉพาะเลนของเรา
                    if (m_axis_tlast) begin
                        next_state = IDLE;
                    end else begin
                        next_flit_cnt = flit_cnt + 1'b1;
                        next_data_reg = data_reg + 1'b1;
                    end
                end
            end
        endcase
    end

    assign m_axis_tdest = {latch_tx, latch_ty};
    assign m_axis_tdata = data_reg;
    assign m_axis_tid   = latch_tid; // ปล่อยป้ายบอกเลน

endmodule

