`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/21/2026 10:31:58 PM
// Design Name: 
// Module Name: loopback_node_agent
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


module loopback_node_agent #(
    // 256 เผื่อไว้เยอะมากสำหรับ echo ที่รับ flit ตามจังหวะ UART
    // ลดเหลือ 16-32 ได้ถ้าอยากให้ backpressure เกิดจริงตอนทดสอบ arbitration
    parameter int DEPTH = 256
)(
    input  logic clk,
    input  logic rst_n,
 
    input  logic [7:0] rx_tdata,
    input  logic [3:0] rx_tdest,
    input  logic [1:0] rx_tid,
    input  logic       rx_tlast,
    input  logic       rx_tvalid,
    output logic [1:0] rx_tready,
 
    output logic [7:0] tx_tdata,
    output logic [3:0] tx_tdest,
    output logic [1:0] tx_tid,
    output logic       tx_tlast,
    output logic       tx_tvalid,
    input  logic [1:0] tx_tready
);
 
    localparam int AW = $clog2(DEPTH);
 
    logic [8:0]    rd_data [0:1];   // {tlast, tdata} ที่หัวคิวของแต่ละ VC
    logic [AW-1:0] wptr    [0:1];
    logic [AW-1:0] rptr    [0:1];
    logic [AW:0]   cnt     [0:1];
    logic [1:0]    wr_en, rd_en;
 
    //--------------------------------------------------------------- ingress
    // แต่ละ VC มี credit ของตัวเอง VC ที่เต็มไม่บล็อก VC อีกตัว
    assign rx_tready[0] = (cnt[0] < DEPTH);
    assign rx_tready[1] = (cnt[1] < DEPTH);
 
    assign wr_en[0] = rx_tvalid && rx_tid[0] && rx_tready[0];
    assign wr_en[1] = rx_tvalid && rx_tid[1] && rx_tready[1];
 
    //--------------------------------------------------------------- storage
    genvar g;
    generate
        for (g = 0; g < 2; g++) begin : GEN_VC
 
            logic [8:0] mem [0:DEPTH-1];
 
            // ห้ามใส่ reset ในบล็อกนี้ ไม่งั้น RAM inference พัง
            always_ff @(posedge clk) begin
                if (wr_en[g]) mem[wptr[g]] <= {rx_tlast, rx_tdata};
            end
 
            assign rd_data[g] = mem[rptr[g]];   // async read = FWFT
 
            // pointer / counter ใส่ async reset ได้ตามปกติ
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    wptr[g] <= '0;
                    rptr[g] <= '0;
                    cnt[g]  <= '0;
                end else begin
                    if (wr_en[g]) wptr[g] <= wptr[g] + 1'b1;
                    if (rd_en[g]) rptr[g] <= rptr[g] + 1'b1;
 
                    if      ( wr_en[g] && !rd_en[g]) cnt[g] <= cnt[g] + 1'b1;
                    else if (!wr_en[g] &&  rd_en[g]) cnt[g] <= cnt[g] - 1'b1;
                end
            end
        end
    endgenerate
 
    //--------------------------------------------------------------- egress
    logic sel;      // VC ที่ "ควรได้คิวถัดไป"
    logic vc_pick;  // VC ที่ถูกเลือกจริงในรอบนี้
 
    always_comb begin
        if (sel == 1'b0) vc_pick = (cnt[0] != 0) ? 1'b0 : 1'b1;
        else             vc_pick = (cnt[1] != 0) ? 1'b1 : 1'b0;
    end
 
    assign tx_tvalid = (cnt[vc_pick] != 0);
    assign tx_tid    = vc_pick ? 2'b10 : 2'b01;
    assign tx_tlast  = rd_data[vc_pick][8];
    assign tx_tdata  = rd_data[vc_pick][7:0];
    assign tx_tdest  = 4'b0000;                  // echo กลับ host node 00
 
    assign rd_en[0] = tx_tvalid && (vc_pick == 1'b0) && tx_tready[0];
    assign rd_en[1] = tx_tvalid && (vc_pick == 1'b1) && tx_tready[1];
 
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)      sel <= 1'b0;
        else if (|rd_en) sel <= ~vc_pick;        // สลับหลังปล่อย flit สำเร็จ
    end

    `ifdef DEBUG_BUILD
    (* mark_debug = "true" *) logic [3:0] rx_tdest_dbg;
        always_ff @(posedge clk) begin
            if (rx_tvalid) rx_tdest_dbg <= rx_tdest;
        end
    
        //-------------------------------------------------------------- ILA taps
        (* mark_debug = "true" *) logic       tx_tvalid_dbg;
        (* mark_debug = "true" *) logic [1:0] tx_tready_dbg;
        (* mark_debug = "true" *) logic       tx_tlast_dbg;
        (* mark_debug = "true" *) logic [7:0] tx_tdata_dbg;
        (* mark_debug = "true" *) logic [1:0] tx_tid_dbg;
        (* mark_debug = "true" *) logic [1:0] rx_tid_dbg;
        (* mark_debug = "true" *) logic       rx_tvalid_dbg;
        (* mark_debug = "true" *) logic [7:0] cnt0_dbg;
        (* mark_debug = "true" *) logic [7:0] cnt1_dbg;
    
        assign tx_tvalid_dbg = tx_tvalid;
        assign tx_tready_dbg = tx_tready;
        assign tx_tlast_dbg  = tx_tlast;
        assign tx_tdata_dbg  = tx_tdata;
        assign tx_tid_dbg    = tx_tid;
        assign rx_tid_dbg    = rx_tid;
        assign rx_tvalid_dbg = rx_tvalid;
        assign cnt0_dbg      = cnt[0][7:0];
        assign cnt1_dbg      = cnt[1][7:0];
    `endif

endmodule
