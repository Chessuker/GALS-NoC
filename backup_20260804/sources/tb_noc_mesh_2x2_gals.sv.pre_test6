`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 07/02/2026 03:03:51 PM
// Design Name: 
// Module Name: tb_noc_mesh_2x2_gals
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


module tb_noc_mesh_2x2_gals;

    parameter DATA_W = 8;
    parameter CORD_W = 2;
    parameter FIFO_DEPTH = 16;
    parameter NUM_VCS = 2; // 🟢 เปิดใช้งาน 2 Virtual Channels

    logic clk_noc;
    logic clk_h00, clk_h10, clk_h01, clk_h11;
    logic rst_n;

    logic               gen_start [3:0];
    logic [1:0]         gen_tx    [3:0];
    logic [1:0]         gen_ty    [3:0];
    logic [7:0]         gen_len   [3:0];
    logic [NUM_VCS-1:0] gen_tid   [3:0]; // 🟢 สัญญาณบอกเลน
    logic               gen_rdy   [3:0];

    // =================================================================
    // สายไฟ 2 ชุด: ชุด Host และ ชุด NoC (เพิ่ม _tid และ _rdy เป็น Array)
    // =================================================================
    
    logic s_h00_val, s_h00_lst; logic [3:0] s_h00_dst; logic [7:0] s_h00_dta;
    logic [NUM_VCS-1:0] s_h00_tid, s_h00_rdy;
    logic m_h00_val, m_h00_lst; logic [3:0] m_h00_dst; logic [7:0] m_h00_dta;
    logic [NUM_VCS-1:0] m_h00_tid, m_h00_rdy;
    
    logic s_h10_val, s_h10_lst; logic [3:0] s_h10_dst; logic [7:0] s_h10_dta;
    logic [NUM_VCS-1:0] s_h10_tid, s_h10_rdy;
    logic m_h10_val, m_h10_lst; logic [3:0] m_h10_dst; logic [7:0] m_h10_dta;
    logic [NUM_VCS-1:0] m_h10_tid, m_h10_rdy;
    
    logic s_h01_val, s_h01_lst; logic [3:0] s_h01_dst; logic [7:0] s_h01_dta;
    logic [NUM_VCS-1:0] s_h01_tid, s_h01_rdy;
    logic m_h01_val, m_h01_lst; logic [3:0] m_h01_dst; logic [7:0] m_h01_dta;
    logic [NUM_VCS-1:0] m_h01_tid, m_h01_rdy;
    
    logic s_h11_val, s_h11_lst; logic [3:0] s_h11_dst; logic [7:0] s_h11_dta;
    logic [NUM_VCS-1:0] s_h11_tid, s_h11_rdy;
    logic m_h11_val, m_h11_lst; logic [3:0] m_h11_dst; logic [7:0] m_h11_dta;
    logic [NUM_VCS-1:0] m_h11_tid, m_h11_rdy;

    logic [3:0] NODE_MY_ID [4] = '{4'h0, 4'h1, 4'h2, 4'h3}; 
    logic [1:0] NODE_TX    [4] = '{2'd0, 2'd1, 2'd0, 2'd1};
    logic [1:0] NODE_TY    [4] = '{2'd0, 2'd0, 2'd1, 2'd1};
    string      NODE_NAME  [4] = '{"00", "10", "01", "11"};

    // =================================================================
    // 📊 Performance Counters
    // =================================================================
    logic perf_en, perf_clear;
    logic [31:0] tx_flits [4], tx_pkts [4], tx_stalls [4], tx_cycles [4];
    logic [31:0] rx_flits [4], rx_pkts [4], rx_stalls [4], rx_cycles [4];

    axis_perf_mon mon_tx_00 (.clk(clk_h00), .rst_n(rst_n), .valid(s_h00_val), .ready(|(s_h00_tid & s_h00_rdy)), .last(s_h00_lst), .clear(perf_clear), .en(perf_en), .flit_cnt(tx_flits[0]), .pkt_cnt(tx_pkts[0]), .stall_cnt(tx_stalls[0]), .active_cnt(tx_cycles[0]));
    axis_perf_mon mon_tx_10 (.clk(clk_h10), .rst_n(rst_n), .valid(s_h10_val), .ready(|(s_h10_tid & s_h10_rdy)), .last(s_h10_lst), .clear(perf_clear), .en(perf_en), .flit_cnt(tx_flits[1]), .pkt_cnt(tx_pkts[1]), .stall_cnt(tx_stalls[1]), .active_cnt(tx_cycles[1]));
    axis_perf_mon mon_tx_01 (.clk(clk_h01), .rst_n(rst_n), .valid(s_h01_val), .ready(|(s_h01_tid & s_h01_rdy)), .last(s_h01_lst), .clear(perf_clear), .en(perf_en), .flit_cnt(tx_flits[2]), .pkt_cnt(tx_pkts[2]), .stall_cnt(tx_stalls[2]), .active_cnt(tx_cycles[2]));
    axis_perf_mon mon_tx_11 (.clk(clk_h11), .rst_n(rst_n), .valid(s_h11_val), .ready(|(s_h11_tid & s_h11_rdy)), .last(s_h11_lst), .clear(perf_clear), .en(perf_en), .flit_cnt(tx_flits[3]), .pkt_cnt(tx_pkts[3]), .stall_cnt(tx_stalls[3]), .active_cnt(tx_cycles[3]));

    axis_perf_mon mon_rx_00 (.clk(clk_h00), .rst_n(rst_n), .valid(m_h00_val), .ready(|(m_h00_tid & m_h00_rdy)), .last(m_h00_lst), .clear(perf_clear), .en(perf_en), .flit_cnt(rx_flits[0]), .pkt_cnt(rx_pkts[0]), .stall_cnt(rx_stalls[0]), .active_cnt(rx_cycles[0]));
    axis_perf_mon mon_rx_10 (.clk(clk_h10), .rst_n(rst_n), .valid(m_h10_val), .ready(|(m_h10_tid & m_h10_rdy)), .last(m_h10_lst), .clear(perf_clear), .en(perf_en), .flit_cnt(rx_flits[1]), .pkt_cnt(rx_pkts[1]), .stall_cnt(rx_stalls[1]), .active_cnt(rx_cycles[1]));
    axis_perf_mon mon_rx_01 (.clk(clk_h01), .rst_n(rst_n), .valid(m_h01_val), .ready(|(m_h01_tid & m_h01_rdy)), .last(m_h01_lst), .clear(perf_clear), .en(perf_en), .flit_cnt(rx_flits[2]), .pkt_cnt(rx_pkts[2]), .stall_cnt(rx_stalls[2]), .active_cnt(rx_cycles[2]));
    axis_perf_mon mon_rx_11 (.clk(clk_h11), .rst_n(rst_n), .valid(m_h11_val), .ready(|(m_h11_tid & m_h11_rdy)), .last(m_h11_lst), .clear(perf_clear), .en(perf_en), .flit_cnt(rx_flits[3]), .pkt_cnt(rx_pkts[3]), .stall_cnt(rx_stalls[3]), .active_cnt(rx_cycles[3]));

    task report_performance(string test_name);
        $display("\n=================================================");
        $display(" PERFORMANCE REPORT: %s", test_name);
        $display("=================================================");
        for (int n = 0; n < 4; n++) begin
            $display(" [Node%s TX] Flits: %0d | Stalls: %0d (%.1f%%)", NODE_NAME[n], tx_flits[n], tx_stalls[n], (tx_cycles[n] > 0) ? (tx_stalls[n]*100.0)/tx_cycles[n] : 0.0);
            $display(" [Node%s RX] Flits: %0d | Stalls: %0d (%.1f%%)", NODE_NAME[n], rx_flits[n], rx_stalls[n], (rx_cycles[n] > 0) ? (rx_stalls[n]*100.0)/rx_cycles[n] : 0.0);
        end
        $display("=================================================\n");
    endtask

    // =================================================================
    // 🎯 VC-Aware Automated Scoreboard
    // =================================================================
    typedef struct packed {
        logic [3:0] src_id;
        logic [3:0] pkt_id;
        logic [7:0] len;
        logic [1:0] vc;
    } noc_txn_meta_t;

    // 🟢 โพยข้อสอบ 3 มิติ: [src_id][dest_idx][vc_id]
    noc_txn_meta_t   exp_meta_q [16][4][NUM_VCS][$];
    logic [7:0]      exp_data_q [16][4][NUM_VCS][$][$];

    int sb_match_cnt    [4] = '{0,0,0,0};
    int sb_mismatch_cnt [4] = '{0,0,0,0};
    int sb_pkt_seq      [16];

    task automatic sb_predict(input [3:0] src_id, input int dest_idx, input int vc_idx, input int len);
        noc_txn_meta_t meta;
        logic [7:0] payload_q[$];
        logic [7:0] running_data;

        meta.src_id = src_id;
        meta.pkt_id = sb_pkt_seq[src_id];
        meta.len    = len[7:0];
        meta.vc     = vc_idx[1:0];

        payload_q.delete();
        running_data = {src_id, 4'h0};
        for (int i = 0; i < len; i++) begin
            payload_q.push_back(running_data);
            running_data = running_data + 8'h1; 
        end

        exp_meta_q[src_id][dest_idx][vc_idx].push_back(meta);
        exp_data_q[src_id][dest_idx][vc_idx].push_back(payload_q);
        sb_pkt_seq[src_id]++;

        $display("[SB-PRED] t=%0t src=0x%0h -> Node%s (VC%0d) pkt_id=%0d len=%0d", $time, src_id, NODE_NAME[dest_idx], vc_idx, meta.pkt_id, len);
    endtask

    function automatic void sb_check(input int dest_idx, input logic [3:0] rx_src, input int vc_idx, ref logic [7:0] rx_payload[$]);
        noc_txn_meta_t   exp_meta;
        logic [7:0]      exp_payload[$];
        bit              mismatch;

        if (exp_meta_q[rx_src][dest_idx][vc_idx].size() == 0) begin
            $display("\n[FATAL ERROR] Node%s (VC%0d) received packet from src=0x%0h but no transaction predicted!", NODE_NAME[dest_idx], vc_idx, rx_src);
            $fatal;
        end

        exp_meta    = exp_meta_q[rx_src][dest_idx][vc_idx].pop_front();
        exp_payload = exp_data_q[rx_src][dest_idx][vc_idx].pop_front();
        mismatch    = 1'b0;

        if (rx_payload.size() !== exp_meta.len) begin
            $display("[SB-MISMATCH][Node%s] length: expected=%0d actual=%0d", NODE_NAME[dest_idx], exp_meta.len, rx_payload.size());
            mismatch = 1'b1;
        end else begin
            for (int i = 0; i < exp_meta.len; i++) begin
                if (rx_payload[i] !== exp_payload[i]) mismatch = 1'b1;
            end
        end

        if (mismatch) begin
            sb_mismatch_cnt[dest_idx]++;
            $display("\n[FATAL ERROR] Scoreboard mismatch on Node%s (VC%0d) (src=0x%0h pkt_id=%0d)", NODE_NAME[dest_idx], vc_idx, exp_meta.src_id, exp_meta.pkt_id);
            $fatal;
        end else begin
            sb_match_cnt[dest_idx]++;
            $display("[SB-PASS] t=%0t Node%s (VC%0d) src=0x%0h pkt_id=%0d len=%0d matches prediction", $time, NODE_NAME[dest_idx], vc_idx, exp_meta.src_id, exp_meta.pkt_id, exp_meta.len);
        end
    endfunction

    // -----------------------------------------------------------------
    // Receiver Blocks (แยกตะกร้ารับตาม VC)
    // -----------------------------------------------------------------
    logic [7:0] act_payload_q [4][NUM_VCS][$];

    always_ff @(posedge clk_h00) begin
        if (!rst_n) begin act_payload_q[0][0].delete(); act_payload_q[0][1].delete(); end
        else if (m_h00_val && |(m_h00_tid & m_h00_rdy)) begin
            automatic int vc = m_h00_tid[1] ? 1 : 0;
            act_payload_q[0][vc].push_back(m_h00_dta);
            if (m_h00_lst) begin
                automatic logic [3:0] rx_src = act_payload_q[0][vc][0][7:4];
                sb_check(0, rx_src, vc, act_payload_q[0][vc]); act_payload_q[0][vc].delete();
            end
        end
    end

    always_ff @(posedge clk_h10) begin
        if (!rst_n) begin act_payload_q[1][0].delete(); act_payload_q[1][1].delete(); end
        else if (m_h10_val && |(m_h10_tid & m_h10_rdy)) begin
            automatic int vc = m_h10_tid[1] ? 1 : 0;
            act_payload_q[1][vc].push_back(m_h10_dta);
            if (m_h10_lst) begin
                automatic logic [3:0] rx_src = act_payload_q[1][vc][0][7:4];
                sb_check(1, rx_src, vc, act_payload_q[1][vc]); act_payload_q[1][vc].delete();
            end
        end
    end

    always_ff @(posedge clk_h01) begin
        if (!rst_n) begin act_payload_q[2][0].delete(); act_payload_q[2][1].delete(); end
        else if (m_h01_val && |(m_h01_tid & m_h01_rdy)) begin
            automatic int vc = m_h01_tid[1] ? 1 : 0;
            act_payload_q[2][vc].push_back(m_h01_dta);
            if (m_h01_lst) begin
                automatic logic [3:0] rx_src = act_payload_q[2][vc][0][7:4];
                sb_check(2, rx_src, vc, act_payload_q[2][vc]); act_payload_q[2][vc].delete();
            end
        end
    end

    always_ff @(posedge clk_h11) begin
        if (!rst_n) begin act_payload_q[3][0].delete(); act_payload_q[3][1].delete(); end
        else if (m_h11_val && |(m_h11_tid & m_h11_rdy)) begin
            automatic int vc = m_h11_tid[1] ? 1 : 0;
            act_payload_q[3][vc].push_back(m_h11_dta);
            if (m_h11_lst) begin
                automatic logic [3:0] rx_src = act_payload_q[3][vc][0][7:4];
                sb_check(3, rx_src, vc, act_payload_q[3][vc]); act_payload_q[3][vc].delete();
            end
        end
    end

    task automatic sb_report_all();
        int total_match = 0, total_mismatch = 0, total_pending = 0;
        $display("\n=================================================");
        $display(" SCOREBOARD REPORT (All Nodes, transaction-level)");
        $display("=================================================");
        for (int d = 0; d < 4; d++) begin
            int pending_d = 0;
            for (int s = 0; s < 16; s++) begin
                for (int v = 0; v < NUM_VCS; v++) pending_d += exp_meta_q[s][d][v].size();
            end
            $display(" [Node%s] Matched: %0d | Mismatched: %0d | Pending: %0d", NODE_NAME[d], sb_match_cnt[d], sb_mismatch_cnt[d], pending_d);
            total_match += sb_match_cnt[d]; total_mismatch += sb_mismatch_cnt[d]; total_pending += pending_d;
        end
        $display("-------------------------------------------------");
        $display(" TOTAL: Matched=%0d Mismatched=%0d Pending=%0d", total_match, total_mismatch, total_pending);
        $display("=================================================\n");
    endtask

    function automatic bit sb_all_passed();
        bit ok = 1'b1;
        for (int d = 0; d < 4; d++) begin
            if (sb_mismatch_cnt[d] != 0) ok = 1'b0;
            for (int s = 0; s < 16; s++) begin
                for (int v = 0; v < NUM_VCS; v++) if (exp_meta_q[s][d][v].size() != 0) ok = 1'b0;
            end
        end
        return ok;
    endfunction

    // =================================================================
    // 5. Instantiation: Mesh, Wrappers, Traffic Gens
    // =================================================================
    logic [3:0]              s_n_val, s_n_lst, m_n_val, m_n_lst;
    logic [3:0][3:0]         s_n_dst, m_n_dst;
    logic [3:0][DATA_W-1:0]  s_n_dta, m_n_dta;
    logic [3:0][NUM_VCS-1:0] s_n_tid, s_n_rdy, m_n_tid, m_n_rdy;

    // 🟢 เปลี่ยนมาเรียกใช้ Mesh ตัวใหม่ที่รองรับ VC !
    noc_mesh_2x2_vc #(
        .DATA_W(DATA_W), .CORD_W(CORD_W), .NUM_VCS(NUM_VCS), .DEPTH(FIFO_DEPTH)
    ) uut_noc (
        .clk(clk_noc), .rst_n(rst_n),
        .s_valid(s_n_val), .s_tlast(s_n_lst), .s_tdest(s_n_dst), .s_tdata(s_n_dta), .s_tid(s_n_tid), .s_ready(s_n_rdy),
        .m_valid(m_n_val), .m_tlast(m_n_lst), .m_tdest(m_n_dst), .m_tdata(m_n_dta), .m_tid(m_n_tid), .m_ready(m_n_rdy)
    );

    // 🟢 อัปเดต Wrapper ให้ต่อกับสายไฟ Array 
    gals_node_wrapper #(.DATA_W(DATA_W), .CORD_W(CORD_W), .DEPTH(FIFO_DEPTH), .NUM_VCS(NUM_VCS)) wrap_00 (.rst_n(rst_n), .clk_host(clk_h00), .s_host_valid(s_h00_val), .s_host_tlast(s_h00_lst), .s_host_tdest(s_h00_dst), .s_host_tdata(s_h00_dta), .s_host_tid(s_h00_tid), .s_host_ready(s_h00_rdy), .m_host_valid(m_h00_val), .m_host_tlast(m_h00_lst), .m_host_tdest(m_h00_dst), .m_host_tdata(m_h00_dta), .m_host_tid(m_h00_tid), .m_host_ready(m_h00_rdy), .clk_noc(clk_noc), .m_noc_valid(s_n_val[0]), .m_noc_tlast(s_n_lst[0]), .m_noc_tdest(s_n_dst[0]), .m_noc_tdata(s_n_dta[0]), .m_noc_tid(s_n_tid[0]), .m_noc_ready(s_n_rdy[0]), .s_noc_valid(m_n_val[0]), .s_noc_tlast(m_n_lst[0]), .s_noc_tdest(m_n_dst[0]), .s_noc_tdata(m_n_dta[0]), .s_noc_tid(m_n_tid[0]), .s_noc_ready(m_n_rdy[0]));
    gals_node_wrapper #(.DATA_W(DATA_W), .CORD_W(CORD_W), .DEPTH(FIFO_DEPTH), .NUM_VCS(NUM_VCS)) wrap_10 (.rst_n(rst_n), .clk_host(clk_h10), .s_host_valid(s_h10_val), .s_host_tlast(s_h10_lst), .s_host_tdest(s_h10_dst), .s_host_tdata(s_h10_dta), .s_host_tid(s_h10_tid), .s_host_ready(s_h10_rdy), .m_host_valid(m_h10_val), .m_host_tlast(m_h10_lst), .m_host_tdest(m_h10_dst), .m_host_tdata(m_h10_dta), .m_host_tid(m_h10_tid), .m_host_ready(m_h10_rdy), .clk_noc(clk_noc), .m_noc_valid(s_n_val[1]), .m_noc_tlast(s_n_lst[1]), .m_noc_tdest(s_n_dst[1]), .m_noc_tdata(s_n_dta[1]), .m_noc_tid(s_n_tid[1]), .m_noc_ready(s_n_rdy[1]), .s_noc_valid(m_n_val[1]), .s_noc_tlast(m_n_lst[1]), .s_noc_tdest(m_n_dst[1]), .s_noc_tdata(m_n_dta[1]), .s_noc_tid(m_n_tid[1]), .s_noc_ready(m_n_rdy[1]));
    gals_node_wrapper #(.DATA_W(DATA_W), .CORD_W(CORD_W), .DEPTH(FIFO_DEPTH), .NUM_VCS(NUM_VCS)) wrap_01 (.rst_n(rst_n), .clk_host(clk_h01), .s_host_valid(s_h01_val), .s_host_tlast(s_h01_lst), .s_host_tdest(s_h01_dst), .s_host_tdata(s_h01_dta), .s_host_tid(s_h01_tid), .s_host_ready(s_h01_rdy), .m_host_valid(m_h01_val), .m_host_tlast(m_h01_lst), .m_host_tdest(m_h01_dst), .m_host_tdata(m_h01_dta), .m_host_tid(m_h01_tid), .m_host_ready(m_h01_rdy), .clk_noc(clk_noc), .m_noc_valid(s_n_val[2]), .m_noc_tlast(s_n_lst[2]), .m_noc_tdest(s_n_dst[2]), .m_noc_tdata(s_n_dta[2]), .m_noc_tid(s_n_tid[2]), .m_noc_ready(s_n_rdy[2]), .s_noc_valid(m_n_val[2]), .s_noc_tlast(m_n_lst[2]), .s_noc_tdest(m_n_dst[2]), .s_noc_tdata(m_n_dta[2]), .s_noc_tid(m_n_tid[2]), .s_noc_ready(m_n_rdy[2]));
    gals_node_wrapper #(.DATA_W(DATA_W), .CORD_W(CORD_W), .DEPTH(FIFO_DEPTH), .NUM_VCS(NUM_VCS)) wrap_11 (.rst_n(rst_n), .clk_host(clk_h11), .s_host_valid(s_h11_val), .s_host_tlast(s_h11_lst), .s_host_tdest(s_h11_dst), .s_host_tdata(s_h11_dta), .s_host_tid(s_h11_tid), .s_host_ready(s_h11_rdy), .m_host_valid(m_h11_val), .m_host_tlast(m_h11_lst), .m_host_tdest(m_h11_dst), .m_host_tdata(m_h11_dta), .m_host_tid(m_h11_tid), .m_host_ready(m_h11_rdy), .clk_noc(clk_noc), .m_noc_valid(s_n_val[3]), .m_noc_tlast(s_n_lst[3]), .m_noc_tdest(s_n_dst[3]), .m_noc_tdata(s_n_dta[3]), .m_noc_tid(s_n_tid[3]), .m_noc_ready(s_n_rdy[3]), .s_noc_valid(m_n_val[3]), .s_noc_tlast(m_n_lst[3]), .s_noc_tdest(m_n_dst[3]), .s_noc_tdata(m_n_dta[3]), .s_noc_tid(m_n_tid[3]), .s_noc_ready(m_n_rdy[3]));

    // Instantiate Traffic Gen
    traffic_gen #(.MY_ID(4'h0), .NUM_VCS(NUM_VCS)) tg_00 (.clk(clk_h00), .rst_n(rst_n), .start(gen_start[0]), .target_x(gen_tx[0]), .target_y(gen_ty[0]), .pkt_len(gen_len[0]), .pkt_tid(gen_tid[0]), .ready_out(gen_rdy[0]), .m_axis_tvalid(s_h00_val), .m_axis_tdata(s_h00_dta), .m_axis_tdest(s_h00_dst), .m_axis_tlast(s_h00_lst), .m_axis_tid(s_h00_tid), .m_axis_tready(s_h00_rdy));
    traffic_gen #(.MY_ID(4'h1), .NUM_VCS(NUM_VCS)) tg_10 (.clk(clk_h10), .rst_n(rst_n), .start(gen_start[1]), .target_x(gen_tx[1]), .target_y(gen_ty[1]), .pkt_len(gen_len[1]), .pkt_tid(gen_tid[1]), .ready_out(gen_rdy[1]), .m_axis_tvalid(s_h10_val), .m_axis_tdata(s_h10_dta), .m_axis_tdest(s_h10_dst), .m_axis_tlast(s_h10_lst), .m_axis_tid(s_h10_tid), .m_axis_tready(s_h10_rdy));
    traffic_gen #(.MY_ID(4'h2), .NUM_VCS(NUM_VCS)) tg_01 (.clk(clk_h01), .rst_n(rst_n), .start(gen_start[2]), .target_x(gen_tx[2]), .target_y(gen_ty[2]), .pkt_len(gen_len[2]), .pkt_tid(gen_tid[2]), .ready_out(gen_rdy[2]), .m_axis_tvalid(s_h01_val), .m_axis_tdata(s_h01_dta), .m_axis_tdest(s_h01_dst), .m_axis_tlast(s_h01_lst), .m_axis_tid(s_h01_tid), .m_axis_tready(s_h01_rdy));
    traffic_gen #(.MY_ID(4'h3), .NUM_VCS(NUM_VCS)) tg_11 (.clk(clk_h11), .rst_n(rst_n), .start(gen_start[3]), .target_x(gen_tx[3]), .target_y(gen_ty[3]), .pkt_len(gen_len[3]), .pkt_tid(gen_tid[3]), .ready_out(gen_rdy[3]), .m_axis_tvalid(s_h11_val), .m_axis_tdata(s_h11_dta), .m_axis_tdest(s_h11_dst), .m_axis_tlast(s_h11_lst), .m_axis_tid(s_h11_tid), .m_axis_tready(s_h11_rdy));

    // ปลายทางพร้อมรับเสมอทั้ง 2 เลน
    assign m_h00_rdy = 2'b11; assign m_h10_rdy = 2'b11; assign m_h01_rdy = 2'b11; assign m_h11_rdy = 2'b11;

    // -----------------------------------------------------------------
    // สัญญาณ Print (Console Output)
    // -----------------------------------------------------------------
    always_ff @(posedge clk_h00) if (rst_n && m_h00_val && |(m_h00_tid & m_h00_rdy)) $display("[%0t ns] Node 00 (VC%0d) rcv: 0x%h", $time, m_h00_tid[1]?1:0, m_h00_dta);
    always_ff @(posedge clk_h10) if (rst_n && m_h10_val && |(m_h10_tid & m_h10_rdy)) $display("[%0t ns] Node 10 (VC%0d) rcv: 0x%h", $time, m_h10_tid[1]?1:0, m_h10_dta);
    always_ff @(posedge clk_h01) if (rst_n && m_h01_val && |(m_h01_tid & m_h01_rdy)) $display("[%0t ns] Node 01 (VC%0d) rcv: 0x%h", $time, m_h01_tid[1]?1:0, m_h01_dta);
    always_ff @(posedge clk_h11) if (rst_n && m_h11_val && |(m_h11_tid & m_h11_rdy)) $display("[%0t ns] Node 11 (VC%0d) rcv: 0x%h", $time, m_h11_tid[1]?1:0, m_h11_dta);

    // -----------------------------------------------------------------
    // Clocks
    // -----------------------------------------------------------------
    initial begin
        clk_noc = 0; clk_h00 = 0; clk_h10 = 0; clk_h01 = 0; clk_h11 = 0;
        fork
            forever #2.0 clk_noc = ~clk_noc;
            forever #1.0 clk_h00 = ~clk_h00;
            forever #4.0 clk_h10 = ~clk_h10;
            forever #1.5 clk_h01 = ~clk_h01;
            forever #5.0 clk_h11 = ~clk_h11;
        join
    end
    initial begin #10000000; $display("\n[Error] Timeout!"); $finish; end

    // -----------------------------------------------------------------
    // Random Traffic Task (🟢 เพิ่มการสุ่ม VC)
    // -----------------------------------------------------------------
    localparam int RAND_PKTS_PER_NODE = 4;
    localparam int RAND_LEN_MIN = 3;
    localparam int RAND_LEN_MAX = 20;

    task automatic random_traffic_node(input int node_idx);
        int dest_idx, len, gap, vc_idx;
        automatic logic [3:0] my_id = NODE_MY_ID[node_idx];
        for (int p = 0; p < RAND_PKTS_PER_NODE; p++) begin
            do dest_idx = $urandom_range(0, 3); while (dest_idx == node_idx);
            len = $urandom_range(RAND_LEN_MIN, RAND_LEN_MAX);
            gap = $urandom_range(5, 40);
            
            vc_idx = $urandom_range(0, 1); // 🟢 สุ่มว่าจะใช้ VC0 หรือ VC1

            #(gap);
            gen_tx[node_idx]  = NODE_TX[dest_idx];
            gen_ty[node_idx]  = NODE_TY[dest_idx];
            gen_len[node_idx] = len[7:0];
            gen_tid[node_idx] = (vc_idx == 1) ? 2'b10 : 2'b01; // 🟢 เลือกบัตรคิว

            sb_predict(my_id, dest_idx, vc_idx, len);
            
            gen_start[node_idx] = 1;
            wait(gen_rdy[node_idx] == 0);
            gen_start[node_idx] = 0;
            wait(gen_rdy[node_idx] == 1);
        end
    endtask

    // -----------------------------------------------------------------
    // Stimulus Block
    // -----------------------------------------------------------------
    initial begin
        rst_n = 0;
        for(int i=0; i<4; i++) begin gen_start[i]=0; gen_tx[i]=0; gen_ty[i]=0; gen_len[i]=0; gen_tid[i]=0; end
        #50 rst_n = 1; #50;

        $display("\n[TB] --- Start GALS Test 1: Fire through diagonal links ---");
        gen_tx[0] = 2'd1; gen_ty[0] = 2'd1; gen_len[0] = 8'd4; gen_tid[0] = 2'b01; sb_predict(4'h0, 3, 0, 4);
        gen_tx[3] = 2'd0; gen_ty[3] = 2'd0; gen_len[3] = 8'd4; gen_tid[3] = 2'b01; sb_predict(4'h3, 0, 0, 4);
        gen_start[0] = 1; gen_start[3] = 1;
        wait(gen_rdy[0] == 0 && gen_rdy[3] == 0); gen_start[0] = 0; gen_start[3] = 0;
        wait(gen_rdy[0] == 1 && gen_rdy[3] == 1);
        #500; $display("[TB] --- Test 1 Finished ---\n");

        // 🚨 ไฮไลท์การแทรกคิว! (VC1 แซง VC0) 🚨
        $display("[TB] --- Start GALS Test 2: VC Preemption Test (Ambulance vs Truck) ---");
        perf_clear = 1; #10; perf_clear = 0; perf_en = 1;

        gen_tx[0] = 2'd1; gen_ty[0] = 2'd0; gen_len[0] = 8'd30; gen_tid[0] = 2'b01; // 🚛 รถบรรทุก (VC0)
        gen_tx[2] = 2'd1; gen_ty[2] = 2'd0; gen_len[2] = 8'd5;  gen_tid[2] = 2'b10; // 🚑 รถพยาบาล (VC1)
        sb_predict(4'h0, 1, 0, 30);
        sb_predict(4'h2, 1, 1, 5);

        gen_start[0] = 1; // ปล่อยรถบรรทุกก่อน
        #50;              // ทิ้งระยะนิดนึง
        gen_start[2] = 1; // ปล่อยรถพยาบาลตามไป!

        wait(gen_rdy[0] == 0 && gen_rdy[2] == 0); gen_start[0] = 0; gen_start[2] = 0;
        wait(gen_rdy[0] == 1 && gen_rdy[2] == 1);
        
        // Drain Phase
        begin
            automatic int timeout = 0;
            while (!sb_all_passed() && timeout < 1000000) begin #100; timeout += 100; end
        end
        #100; perf_en = 0;
        $display("[TB] --- Test 2 Finished ---\n");
        report_performance("VC Preemption Test");
        sb_report_all();

        $display("\n[TB] --- Start GALS Test 3: Random All-to-All Traffic with VCs ---");
        perf_clear = 1; #10; perf_clear = 0; perf_en = 1;
        fork
            random_traffic_node(0); random_traffic_node(1); random_traffic_node(2); random_traffic_node(3);
        join
        begin
            int timeout = 0;
            while (!sb_all_passed() && timeout < 5000000) begin #500; timeout += 500; end
        end
        #100; perf_en = 0;
        $display("[TB] --- Test 3 Finished ---\n");
        report_performance("Random All-to-All Traffic");
        sb_report_all();

        $display("[TB] --- Test 3 Finished ---\n");
        report_performance("Random All-to-All Traffic");
        sb_report_all();

        $display("\n[TB] --- Start GALS Test 4: Multi-Port Contention (Fairness Test) ---");
        perf_clear = 1; #10; perf_clear = 0; perf_en = 1;

        // Node 00 (x=0,y=0), Node 01 (x=0,y=1), Node 11 (x=1,y=1)
        // รุมยิงไปหาเป้าหมายเดียวกันคือ Node 10 (x=1,y=0) พร้อมกัน!
        // ใช้เลนปกติ (VC0) ทั้งหมด เพื่อบีบให้ Arbiter ต้องแชร์ถนนกัน
        gen_tx[0] = 2'd1; gen_ty[0] = 2'd0; gen_len[0] = 8'd20; gen_tid[0] = 2'b01;
        gen_tx[2] = 2'd1; gen_ty[2] = 2'd0; gen_len[2] = 8'd20; gen_tid[2] = 2'b01;
        gen_tx[3] = 2'd1; gen_ty[3] = 2'd0; gen_len[3] = 8'd20; gen_tid[3] = 2'b01;

        // สั่ง Scoreboard ให้รอรับของ
        sb_predict(4'h0, 1, 0, 20); // Node 00 -> Node 10
        sb_predict(4'h2, 1, 0, 20); // Node 01 -> Node 10
        sb_predict(4'h3, 1, 0, 20); // Node 11 -> Node 10

        // กดปุ่ม Start พร้อมกัน 3 โหนด
        gen_start[0] = 1; gen_start[2] = 1; gen_start[3] = 1;
        wait(gen_rdy[0] == 0 && gen_rdy[2] == 0 && gen_rdy[3] == 0); 
        gen_start[0] = 0; gen_start[2] = 0; gen_start[3] = 0;
        wait(gen_rdy[0] == 1 && gen_rdy[2] == 1 && gen_rdy[3] == 1);

        // รอจนกว่าจะโอนถ่ายข้อมูลเสร็จ (Drain Phase)
        begin
            automatic int timeout = 0;
            while (!sb_all_passed() && timeout < 5000000) begin #500; timeout += 500; end
        end
        #100; perf_en = 0;
        
        $display("[TB] --- Test 4 Finished ---\n");
        report_performance("Multi-Port Contention (Fairness Test)");
        sb_report_all();

        $display("\n[TB] --- Start GALS Test 5: Starvation Override Proof (VC1 Flood vs VC0) ---");
        perf_clear = 1; #10; perf_clear = 0; perf_en = 1;

        // 1. ปล่อยรถบรรทุก (VC0) ขบวนยาว 50 ฟลิต จาก Node 00 ไป Node 10
        gen_tx[0] = 2'd1; gen_ty[0] = 2'd0; gen_len[0] = 8'd50; gen_tid[0] = 2'b01;
        sb_predict(4'h0, 1, 0, 50);
        
        gen_start[0] = 1;
        #20; // รอให้ VC0 เข้าไปจ่อที่สี่แยก
        gen_start[0] = 0;

        // 2. ปล่อยรถพยาบาล (VC1) กระหน่ำยิงรัวๆ จาก Node 01 ไป Node 10
        // จำนวน 10 แพ็กเกจ แพ็กเกจละ 15 ฟลิต (รวม 150 ฟลิต แย่งเลนต่อเนื่อง)
        for (int i = 0; i < 10; i++) begin
            gen_tx[2] = 2'd1; gen_ty[2] = 2'd0; gen_len[2] = 8'd15; gen_tid[2] = 2'b10;
            sb_predict(4'h2, 1, 1, 15);
            
            gen_start[2] = 1;
            wait(gen_rdy[2] == 0);
            gen_start[2] = 0;
            wait(gen_rdy[2] == 1);
        end

        // รอจนกว่าแพ็กเกจทั้งหมดจะส่งถึงปลายทาง
        begin
            automatic int timeout = 0;
            while (!sb_all_passed() && timeout < 5000000) begin #500; timeout += 500; end
        end
        #100; perf_en = 0;
        
        $display("[TB] --- Test 5 Finished ---\n");
        report_performance("Starvation Override Proof");
        sb_report_all();

        $finish;
    end

endmodule
