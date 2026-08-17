`timescale 1ns / 1ps

module arty_gals_noc_wrapper (
    input  logic clk_100mhz,
    input  logic rst_n_btn,

    input  logic uart_rxd,
    output logic uart_txd,

    output logic [3:0] led
);

    logic clk_noc, clk_h00, clk_h01, clk_h10, clk_h11;
    logic pll_locked;
    logic global_rst_n;

    clk_wiz_0 clk_gen (
        .clk_in1(clk_100mhz),
        .reset(~rst_n_btn),
        .clk_out1(clk_noc),
        .clk_out2(clk_h00),
        .clk_out3(clk_h01),
        .clk_out4(clk_h10),
        .clk_out5(clk_h11),
        .locked(pll_locked)
    );

    assign global_rst_n = rst_n_btn & pll_locked;

    logic [7:0] t00_tx_data; logic [3:0] t00_tx_dest; logic [1:0] t00_tx_tid; logic t00_tx_tlast; logic t00_tx_valid; logic [1:0] t00_tx_ready;
    logic [7:0] t00_rx_data; logic [3:0] t00_rx_dest; logic [1:0] t00_rx_tid; logic t00_rx_tlast; logic t00_rx_valid; logic [1:0] t00_rx_ready;

    logic [7:0] t01_tx_data; logic [3:0] t01_tx_dest; logic [1:0] t01_tx_tid; logic t01_tx_tlast; logic t01_tx_valid; logic [1:0] t01_tx_ready;
    logic [7:0] t01_rx_data; logic [3:0] t01_rx_dest; logic [1:0] t01_rx_tid; logic t01_rx_tlast; logic t01_rx_valid; logic [1:0] t01_rx_ready;

    logic [7:0] t10_tx_data; logic [3:0] t10_tx_dest; logic [1:0] t10_tx_tid; logic t10_tx_tlast; logic t10_tx_valid; logic [1:0] t10_tx_ready;
    logic [7:0] t10_rx_data; logic [3:0] t10_rx_dest; logic [1:0] t10_rx_tid; logic t10_rx_tlast; logic t10_rx_valid; logic [1:0] t10_rx_ready;

    logic [7:0] t11_tx_data; logic [3:0] t11_tx_dest; logic [1:0] t11_tx_tid; logic t11_tx_tlast; logic t11_tx_valid; logic [1:0] t11_tx_ready;
    logic [7:0] t11_rx_data; logic [3:0] t11_rx_dest; logic [1:0] t11_rx_tid; logic t11_rx_tlast; logic t11_rx_valid; logic [1:0] t11_rx_ready;

    gals_noc_top uut_noc_top (
        .clk_noc(clk_noc), .rst_n(global_rst_n),
        .clk_h00(clk_h00), .clk_h01(clk_h01), .clk_h10(clk_h10), .clk_h11(clk_h11),

        .h00_tx_tdata(t00_tx_data), .h00_tx_tdest(t00_tx_dest), .h00_tx_tid(t00_tx_tid), .h00_tx_tlast(t00_tx_tlast), .h00_tx_tvalid(t00_tx_valid), .h00_tx_tready(t00_tx_ready),
        .h00_rx_tdata(t00_rx_data), .h00_rx_tdest(t00_rx_dest), .h00_rx_tid(t00_rx_tid), .h00_rx_tlast(t00_rx_tlast), .h00_rx_tvalid(t00_rx_valid), .h00_rx_tready(t00_rx_ready),

        .h01_tx_tdata(t01_tx_data), .h01_tx_tdest(t01_tx_dest), .h01_tx_tid(t01_tx_tid), .h01_tx_tlast(t01_tx_tlast), .h01_tx_tvalid(t01_tx_valid), .h01_tx_tready(t01_tx_ready),
        .h01_rx_tdata(t01_rx_data), .h01_rx_tdest(t01_rx_dest), .h01_rx_tid(t01_rx_tid), .h01_rx_tlast(t01_rx_tlast), .h01_rx_tvalid(t01_rx_valid), .h01_rx_tready(t01_rx_ready),

        .h10_tx_tdata(t10_tx_data), .h10_tx_tdest(t10_tx_dest), .h10_tx_tid(t10_tx_tid), .h10_tx_tlast(t10_tx_tlast), .h10_tx_tvalid(t10_tx_valid), .h10_tx_tready(t10_tx_ready),
        .h10_rx_tdata(t10_rx_data), .h10_rx_tdest(t10_rx_dest), .h10_rx_tid(t10_rx_tid), .h10_rx_tlast(t10_rx_tlast), .h10_rx_tvalid(t10_rx_valid), .h10_rx_tready(t10_rx_ready),

        .h11_tx_tdata(t11_tx_data), .h11_tx_tdest(t11_tx_dest), .h11_tx_tid(t11_tx_tid), .h11_tx_tlast(t11_tx_tlast), .h11_tx_tvalid(t11_tx_valid), .h11_tx_tready(t11_tx_ready),
        .h11_rx_tdata(t11_rx_data), .h11_rx_tdest(t11_rx_dest), .h11_rx_tid(t11_rx_tid), .h11_rx_tlast(t11_rx_tlast), .h11_rx_tvalid(t11_rx_valid), .h11_rx_tready(t11_rx_ready)
    );

    uart_noc_host #(
        .CLK_FREQ(100_000_000),
        .BAUD_RATE(3_000_000)
    ) host_00 (
        .clk(clk_h00), .rst_n(global_rst_n),
        .uart_rxd(uart_rxd), .uart_txd(uart_txd),
        .tx_tdata(t00_tx_data), .tx_tdest(t00_tx_dest), .tx_tid(t00_tx_tid), .tx_tlast(t00_tx_tlast), .tx_tvalid(t00_tx_valid), .tx_tready(t00_tx_ready),
        .rx_tdata(t00_rx_data), .rx_tdest(t00_rx_dest), .rx_tid(t00_rx_tid), .rx_tlast(t00_rx_tlast), .rx_tvalid(t00_rx_valid), .rx_tready(t00_rx_ready)
    );

    loopback_node_agent echo_01 (
        .clk(clk_h01), .rst_n(global_rst_n),
        .rx_tdata(t01_rx_data), .rx_tdest(t01_rx_dest), .rx_tid(t01_rx_tid), .rx_tlast(t01_rx_tlast), .rx_tvalid(t01_rx_valid), .rx_tready(t01_rx_ready),
        .tx_tdata(t01_tx_data), .tx_tdest(t01_tx_dest), .tx_tid(t01_tx_tid), .tx_tlast(t01_tx_tlast), .tx_tvalid(t01_tx_valid), .tx_tready(t01_tx_ready)
    );

    loopback_node_agent echo_10 (
        .clk(clk_h10), .rst_n(global_rst_n),
        .rx_tdata(t10_rx_data), .rx_tdest(t10_rx_dest), .rx_tid(t10_rx_tid), .rx_tlast(t10_rx_tlast), .rx_tvalid(t10_rx_valid), .rx_tready(t10_rx_ready),
        .tx_tdata(t10_tx_data), .tx_tdest(t10_tx_dest), .tx_tid(t10_tx_tid), .tx_tlast(t10_tx_tlast), .tx_tvalid(t10_tx_valid), .tx_tready(t10_tx_ready)
    );

    loopback_node_agent echo_11 (
        .clk(clk_h11), .rst_n(global_rst_n),
        .rx_tdata(t11_rx_data), .rx_tdest(t11_rx_dest), .rx_tid(t11_rx_tid), .rx_tlast(t11_rx_tlast), .rx_tvalid(t11_rx_valid), .rx_tready(t11_rx_ready),
        .tx_tdata(t11_tx_data), .tx_tdest(t11_tx_dest), .tx_tid(t11_tx_tid), .tx_tlast(t11_tx_tlast), .tx_tvalid(t11_tx_valid), .tx_tready(t11_tx_ready)
    );

    logic [26:0] heartbeat_cnt;
    always_ff @(posedge clk_h00 or negedge global_rst_n) begin
        if (!global_rst_n) heartbeat_cnt <= '0;
        else heartbeat_cnt <= heartbeat_cnt + 1'b1;
    end

    assign led[0] = heartbeat_cnt[26];
    assign led[1] = ~uart_rxd;
    assign led[2] = ~uart_txd;

    assign led[3] = (t01_tx_valid | t10_tx_valid | t11_tx_valid);

endmodule
`timescale 1ns / 1ps

module async_fifo#(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
)(
    input logic wclk,
    input logic wrst_n,
    input logic w_en,
    input logic [DATA_WIDTH-1:0] wdata,
    output logic wfull,
    (* DONT_TOUCH = "TRUE" *) output logic [ADDR_WIDTH:0] w_level,

    input logic rclk,
    input logic rrst_n,
    input logic r_en,
    output logic [DATA_WIDTH-1:0] rdata,
    output logic rempty,

    output logic almost_full,
    input  logic [ADDR_WIDTH:0] prog_full_thresh,

    output logic almost_empty,
    input  logic [ADDR_WIDTH:0] prog_empty_thresh,

    output logic ecc_single_err,
    output logic ecc_double_err
);

    logic [ADDR_WIDTH-1:0] waddr, raddr;
    logic [ADDR_WIDTH:0] wptr_g, rptr_g;
    logic [ADDR_WIDTH:0] wptr_g_sync, rptr_g_sync;

    `ifdef FORMAL
        dual_port_ram #(
            .DATA_WIDTH(DATA_WIDTH),
            .ADDR_WIDTH(ADDR_WIDTH)
        ) dp_ram (
            .wclk(wclk), .w_en(w_en && !wfull), .waddr(waddr), .wdata(wdata),
            .rclk(rclk), .r_en(r_en && !rempty), .raddr(raddr), .rdata(rdata)
        );
        assign ecc_single_err = 1'b0;
        assign ecc_double_err = 1'b0;

    `else
        logic [7:0] rdata_ecc;

        dual_port_ram_ecc #(
            .DATA_WIDTH(8),
            .ADDR_WIDTH(ADDR_WIDTH)
        ) dp_ram_ecc_inst (
            .wclk(wclk),
            .w_en(w_en && !wfull),
            .waddr(waddr),
            .wdata(wdata[7:0]),
            .rclk(rclk),
            .r_en(r_en && !rempty),
            .raddr(raddr),
            .rdata(rdata_ecc),
            .ecc_single_err(ecc_single_err),
            .ecc_double_err(ecc_double_err)
        );

        generate
            if (DATA_WIDTH > 8) begin : GEN_CTRL_RAM
                logic [(DATA_WIDTH-8)-1:0] rdata_ctrl;

                dual_port_ram #(
                    .DATA_WIDTH(DATA_WIDTH - 8),
                    .ADDR_WIDTH(ADDR_WIDTH)
                ) dp_ram_ctrl_inst (
                    .wclk(wclk),
                    .w_en(w_en && !wfull),
                    .waddr(waddr),
                    .wdata(wdata[DATA_WIDTH-1 : 8]),
                    .rclk(rclk),
                    .r_en(r_en && !rempty),
                    .raddr(raddr),
                    .rdata(rdata_ctrl)
                );

                assign rdata = {rdata_ctrl, rdata_ecc};

            end else begin : GEN_NO_CTRL
                assign rdata = rdata_ecc;
            end
        endgenerate
    `endif

    gray_counter #(ADDR_WIDTH) w_cnt (
        .clk(wclk), .rst(!wrst_n), .en(w_en && !wfull), .ptr_g(wptr_g), .addr(waddr)
    );
    gray_counter #(ADDR_WIDTH) r_cnt (
        .clk(rclk), .rst(!rrst_n), .en(r_en && !rempty), .ptr_g(rptr_g), .addr(raddr)
    );
    sync_2stage #(ADDR_WIDTH+1) sync_w2r (
        .clk(rclk), .rst(!rrst_n), .d(wptr_g), .q(wptr_g_sync)
    );
    sync_2stage #(ADDR_WIDTH+1) sync_r2w (
        .clk(wclk), .rst(!wrst_n), .d(rptr_g), .q(rptr_g_sync)
    );

    assign rempty = (wptr_g_sync == rptr_g);
    assign wfull = (wptr_g == {~rptr_g_sync[ADDR_WIDTH], ~rptr_g_sync[ADDR_WIDTH-1], rptr_g_sync[ADDR_WIDTH-2:0]});

    logic [ADDR_WIDTH:0] wptr_bin;
    logic [ADDR_WIDTH:0] rptr_bin_sync;

    always_comb begin
        wptr_bin[ADDR_WIDTH] = wptr_g[ADDR_WIDTH];
        for (int i = ADDR_WIDTH-1; i >= 0; i--) wptr_bin[i] = wptr_bin[i+1] ^ wptr_g[i];
    end

    always_comb begin
        rptr_bin_sync[ADDR_WIDTH] = rptr_g_sync[ADDR_WIDTH];
        for (int i = ADDR_WIDTH-1; i >= 0; i--) rptr_bin_sync[i] = rptr_bin_sync[i+1] ^ rptr_g_sync[i];
    end

    assign w_level = wptr_bin - rptr_bin_sync;
    assign almost_full = (w_level >= prog_full_thresh);

    logic [ADDR_WIDTH:0] rptr_bin;
    logic [ADDR_WIDTH:0] wptr_bin_sync;

    always_comb begin
        rptr_bin[ADDR_WIDTH] = rptr_g[ADDR_WIDTH];
        for (int i = ADDR_WIDTH-1; i >= 0; i--) rptr_bin[i] = rptr_bin[i+1] ^ rptr_g[i];
    end

    always_comb begin
        wptr_bin_sync[ADDR_WIDTH] = wptr_g_sync[ADDR_WIDTH];
        for (int i = ADDR_WIDTH-1; i >= 0; i--) wptr_bin_sync[i] = wptr_bin_sync[i+1] ^ wptr_g_sync[i];
    end

    logic [ADDR_WIDTH:0] r_level;
    assign r_level = wptr_bin_sync - rptr_bin;
    assign almost_empty = (r_level <= prog_empty_thresh);

endmodule

`timescale 1ns / 1ps

module async_fifo_fwft #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
)(

    input  logic                  wclk,
    input  logic                  wrst_n,
    input  logic                  w_en,
    input  logic [DATA_WIDTH-1:0] wdata,
    output logic                  wfull,

    output logic                  almost_full,
    input  logic [ADDR_WIDTH:0]   prog_full_thresh,

    input  logic                  rclk,
    input  logic                  rrst_n,
    input  logic                  r_en,
    output logic [DATA_WIDTH-1:0] rdata,
    output logic                  rempty,

    output logic                  ecc_single_err,
    output logic                  ecc_double_err
);

    logic                  internal_rempty;
    logic [DATA_WIDTH-1:0] internal_rdata;
    logic                  internal_r_en;

    async_fifo #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) core_fifo (

        .wclk(wclk),
        .wrst_n(wrst_n),
        .w_en(w_en),
        .wdata(wdata),
        .wfull(wfull),

        .w_level(),
        .almost_full(almost_full),
        .prog_full_thresh(prog_full_thresh),
        .almost_empty(),
        .prog_empty_thresh('0),
        .ecc_single_err(ecc_single_err),
        .ecc_double_err(ecc_double_err),

        .rclk(rclk),
        .rrst_n(rrst_n),
        .r_en(internal_r_en),
        .rdata(internal_rdata),
        .rempty(internal_rempty)
    );

    fwft_wrapper #(
        .DATA_WIDTH(DATA_WIDTH)
    ) fwft_inst (
        .clk(rclk),
        .rst_n(rrst_n),

        .f_rempty(internal_rempty),
        .f_rdata(internal_rdata),
        .f_r_en(internal_r_en),

        .fwft_rempty(rempty),
        .fwft_rdata(rdata),
        .fwft_r_en(r_en)
    );

endmodule

`timescale 1ns / 1ps

module axis_perf_mon (
    input logic clk,
    input logic rst_n,

    input logic valid,
    input logic ready,
    input logic last,

    input logic clear,
    input logic en,

    output logic [31:0] flit_cnt,
    output logic [31:0] pkt_cnt,
    output logic [31:0] stall_cnt,
    output logic [31:0] active_cnt
);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            flit_cnt   <= '0;
            pkt_cnt    <= '0;
            stall_cnt  <= '0;
            active_cnt <= '0;
        end else if (clear) begin
            flit_cnt   <= '0;
            pkt_cnt    <= '0;
            stall_cnt  <= '0;
            active_cnt <= '0;
        end else if (en) begin

            active_cnt <= active_cnt + 1'b1;

            if (valid && ready) begin
                flit_cnt <= flit_cnt + 1'b1;
                if (last) pkt_cnt <= pkt_cnt + 1'b1;
            end

            if (valid && !ready) begin
                stall_cnt <= stall_cnt + 1'b1;
            end
        end
    end

endmodule

`timescale 1ns / 1ps

module dual_port_ram #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
)(

    input logic wclk,
    input logic w_en,
    input logic [ADDR_WIDTH-1:0] waddr,
    input logic [DATA_WIDTH-1:0] wdata,

    input logic rclk,
    input logic r_en,
    input logic [ADDR_WIDTH-1:0] raddr,
    output logic [DATA_WIDTH-1:0] rdata
    );

    localparam  DEPTH = 1 << ADDR_WIDTH;

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    always_ff @(posedge wclk) begin
        if(w_en) begin
            mem[waddr] <= wdata;
        end
    end

    always_ff @(posedge rclk) begin
        if(r_en) begin
            rdata <= mem[raddr];
        end
    end
endmodule

`timescale 1ns / 1ps

module dual_port_ram_ecc #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 4
)(
    input  logic                  wclk,
    input  logic                  w_en,
    input  logic [ADDR_WIDTH-1:0] waddr,
    input  logic [DATA_WIDTH-1:0] wdata,

    input  logic                  rclk,
    input  logic                  r_en,
    input  logic [ADDR_WIDTH-1:0] raddr,
    output logic [DATA_WIDTH-1:0] rdata,

    output logic                  ecc_single_err,
    output logic                  ecc_double_err
);

    localparam ECC_WIDTH = 5;
    localparam TOTAL_WIDTH = DATA_WIDTH + ECC_WIDTH;

    logic [TOTAL_WIDTH-1:0] encoded_wdata;
    logic [TOTAL_WIDTH-1:0] raw_rdata;

    ecc_secded_encode_8b encoder (
        .data_in(wdata),
        .encoded_out(encoded_wdata)
    );

    dual_port_ram #(
        .DATA_WIDTH(TOTAL_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) core_ram (
        .wclk(wclk), .w_en(w_en), .waddr(waddr), .wdata(encoded_wdata),
        .rclk(rclk), .r_en(r_en), .raddr(raddr), .rdata(raw_rdata)
    );

    ecc_secded_decode_8b decoder (
        .encoded_in(raw_rdata),
        .data_out(rdata),
        .single_err(ecc_single_err),
        .double_err(ecc_double_err)
    );

    `ifdef FORMAL

        (* anyconst *) logic [ADDR_WIDTH-1:0] f_track_addr;

        reg [DATA_WIDTH-1:0]  f_gold_data;
        reg [TOTAL_WIDTH-1:0] f_encoded_gold;
        reg                   f_data_written = 1'b0;

        always_ff @(posedge wclk) begin
            if (w_en && (waddr == f_track_addr)) begin
                f_gold_data    <= wdata;
                f_encoded_gold <= encoded_wdata;
                f_data_written <= 1'b1;
            end
        end

        wire [TOTAL_WIDTH-1:0] f_correct_encoded;
        ecc_secded_encode_8b f_formal_enc (
            .data_in(f_gold_data),
            .encoded_out(f_correct_encoded)
        );

        reg                  f_read_req = 1'b0;
        reg [DATA_WIDTH-1:0] f_expected_data;

        always_ff @(posedge rclk) begin
            if (r_en && f_data_written && (raddr == f_track_addr)) begin
                f_read_req      <= 1'b1;
                f_expected_data <= f_gold_data;
            end else begin
                f_read_req      <= 1'b0;
            end
        end

        always @(*) begin
            if (f_data_written) begin
                assume(f_encoded_gold == f_correct_encoded);
                assume(core_ram.mem[f_track_addr] == f_encoded_gold);
            end

            if (f_read_req) begin

                assume(f_data_written == 1'b1);
                assume(raw_rdata == f_encoded_gold);
                assume(f_expected_data == f_gold_data);
            end

            assume(!(w_en && r_en && (waddr == f_track_addr) && (raddr == f_track_addr)));
        end

        always @(posedge rclk) begin
            if (f_read_req) begin
                if (!ecc_double_err) begin
                    assert_ram_address_integrity: assert(rdata == f_expected_data);

                    cover_clean_read: cover(!ecc_single_err);
                end
            end
        end
    `endif

endmodule

`timescale 1ns / 1ps

module ecc_secded_decode_8b (
    input  logic [12:0] encoded_in,
    output logic [7:0]  data_out,
    output logic        single_err,
    output logic        double_err
);
    logic p0_in;
    logic [11:0] word_in;
    assign p0_in = encoded_in[12];
    assign word_in = encoded_in[11:0];

    logic s1, s2, s4, s8;
    assign s1 = word_in[0] ^ word_in[2] ^ word_in[4] ^ word_in[6] ^ word_in[8] ^ word_in[10];
    assign s2 = word_in[1] ^ word_in[2] ^ word_in[5] ^ word_in[6] ^ word_in[9] ^ word_in[10];
    assign s4 = word_in[3] ^ word_in[4] ^ word_in[5] ^ word_in[6] ^ word_in[11];
    assign s8 = word_in[7] ^ word_in[8] ^ word_in[9] ^ word_in[10] ^ word_in[11];

    logic [3:0] syndrome;
    assign syndrome = {s8, s4, s2, s1};

    logic overall_parity_calc;
    assign overall_parity_calc = ^word_in;
    logic parity_mismatch;
    assign parity_mismatch = (overall_parity_calc != p0_in);

    always_comb begin
        single_err = 1'b0;
        double_err = 1'b0;

        if (syndrome != 0) begin
            if (parity_mismatch) begin
                single_err = 1'b1;
            end else begin
                double_err = 1'b1;
            end
        end else if (parity_mismatch) begin
            single_err = 1'b1;
        end
    end

    logic [11:0] corrected_word;
    always_comb begin
        corrected_word = word_in;
        if (single_err && syndrome != 0) begin
            corrected_word[syndrome - 1] = ~corrected_word[syndrome - 1];
        end
    end

    assign data_out = {corrected_word[11:8], corrected_word[6:4], corrected_word[2]};
endmodule

`timescale 1ns / 1ps

module ecc_secded_encode_8b (
    input  logic [7:0]  data_in,
    output logic [12:0] encoded_out
);
    logic p1, p2, p4, p8, p0;

    assign p1 = data_in[0] ^ data_in[1] ^ data_in[3] ^ data_in[4] ^ data_in[6];
    assign p2 = data_in[0] ^ data_in[2] ^ data_in[3] ^ data_in[5] ^ data_in[6];
    assign p4 = data_in[1] ^ data_in[2] ^ data_in[3] ^ data_in[7];
    assign p8 = data_in[4] ^ data_in[5] ^ data_in[6] ^ data_in[7];

    logic [11:0] hamming_word;
    assign hamming_word = {data_in[7:4], p8, data_in[3:1], p4, data_in[0], p2, p1};

    assign p0 = ^hamming_word;

    assign encoded_out = {p0, hamming_word};
endmodule

`timescale 1ns / 1ps

module fwft_wrapper #(
    parameter DATA_WIDTH = 8
)(
    input  logic clk,
    input  logic rst_n,

    input  logic                  f_rempty,
    input  logic [DATA_WIDTH-1:0] f_rdata,
    output logic                  f_r_en,

    output logic                  fwft_rempty,
    output logic [DATA_WIDTH-1:0] fwft_rdata,
    input  logic                  fwft_r_en
);

    logic                  out_valid;
    logic [DATA_WIDTH-1:0] out_data;

    logic                  skid_valid;
    logic [DATA_WIDTH-1:0] skid_data;

    logic data_arriving;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) data_arriving <= 1'b0;
        else        data_arriving <= f_r_en;
    end

    logic user_read;
    assign user_read = fwft_r_en && out_valid;

    logic [1:0] valid_count;
    assign valid_count = out_valid + skid_valid + data_arriving;

    logic can_read;
    always_comb begin

        if (user_read) can_read = (valid_count <= 2);
        else           can_read = (valid_count <= 1);
    end

    assign f_r_en = !f_rempty && can_read;

    assign fwft_rempty = !out_valid;
    assign fwft_rdata  = out_data;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_valid  <= 1'b0;
            skid_valid <= 1'b0;
            out_data   <= '0;
            skid_data  <= '0;
        end else begin

            if (user_read || !out_valid) begin
                if (skid_valid) begin
                    out_valid <= 1'b1;
                    out_data  <= skid_data;
                end else if (data_arriving) begin
                    out_valid <= 1'b1;
                    out_data  <= f_rdata;
                end else begin
                    out_valid <= 1'b0;
                end
            end

            if (data_arriving) begin
                if (user_read || !out_valid) begin
                    if (skid_valid) begin
                        skid_valid <= 1'b1;
                        skid_data  <= f_rdata;
                    end else begin
                        skid_valid <= 1'b0;
                    end
                end else begin

                    skid_valid <= 1'b1;
                    skid_data  <= f_rdata;
                end
            end else begin

                if (user_read || !out_valid) begin
                    skid_valid <= 1'b0;
                end
            end
        end
    end

    `ifdef FORMAL
        reg f_past_valid = 1'b0;
        always @(posedge clk) f_past_valid <= 1'b1;

        always @(*) begin

            if (!f_past_valid) assume(!rst_n);
        end

        always @(*) begin
            if (rst_n) begin

                assert_no_overflow: assert(valid_count <= 2);

                if (skid_valid) begin
                    assert_skid_physics: assert(out_valid == 1'b1);
                end

                assert_empty_status: assert(fwft_rempty == !out_valid);

            end else begin

                assert_reset_out:  assert(out_valid == 1'b0);
                assert_reset_skid: assert(skid_valid == 1'b0);
                assert_reset_arr:  assert(data_arriving == 1'b0);
            end
        end
    `endif

endmodule

`timescale 1ns / 1ps

module gals_noc_top (

    input  logic clk_noc,
    input  logic rst_n,

    input  logic clk_h00,
    input  logic clk_h01,
    input  logic clk_h10,
    input  logic clk_h11,

    input  logic [7:0] h00_tx_tdata,
    input  logic [3:0] h00_tx_tdest,
    input  logic [1:0] h00_tx_tid,
    input  logic       h00_tx_tlast,
    input  logic       h00_tx_tvalid,
    output logic [1:0] h00_tx_tready,

    output logic [7:0] h00_rx_tdata,
    output logic [3:0] h00_rx_tdest,
    output logic [1:0] h00_rx_tid,
    output logic       h00_rx_tlast,
    output logic       h00_rx_tvalid,
    input  logic [1:0] h00_rx_tready,

    input  logic [7:0] h01_tx_tdata,
    input  logic [3:0] h01_tx_tdest,
    input  logic [1:0] h01_tx_tid,
    input  logic       h01_tx_tlast,
    input  logic       h01_tx_tvalid,
    output logic [1:0] h01_tx_tready,

    output logic [7:0] h01_rx_tdata,
    output logic [3:0] h01_rx_tdest,
    output logic [1:0] h01_rx_tid,
    output logic       h01_rx_tlast,
    output logic       h01_rx_tvalid,
    input  logic [1:0] h01_rx_tready,

    input  logic [7:0] h10_tx_tdata,
    input  logic [3:0] h10_tx_tdest,
    input  logic [1:0] h10_tx_tid,
    input  logic       h10_tx_tlast,
    input  logic       h10_tx_tvalid,
    output logic [1:0] h10_tx_tready,

    output logic [7:0] h10_rx_tdata,
    output logic [3:0] h10_rx_tdest,
    output logic [1:0] h10_rx_tid,
    output logic       h10_rx_tlast,
    output logic       h10_rx_tvalid,
    input  logic [1:0] h10_rx_tready,

    input  logic [7:0] h11_tx_tdata,
    input  logic [3:0] h11_tx_tdest,
    input  logic [1:0] h11_tx_tid,
    input  logic       h11_tx_tlast,
    input  logic       h11_tx_tvalid,
    output logic [1:0] h11_tx_tready,

    output logic [7:0] h11_rx_tdata,
    output logic [3:0] h11_rx_tdest,
    output logic [1:0] h11_rx_tid,
    output logic       h11_rx_tlast,
    output logic       h11_rx_tvalid,
    input  logic [1:0] h11_rx_tready
);

    logic [3:0][7:0] noc_tx_tdata;
    logic [3:0][3:0] noc_tx_tdest;
    logic [3:0][1:0] noc_tx_tid;
    logic [3:0]      noc_tx_tlast;
    logic [3:0]      noc_tx_tvalid;
    logic [3:0][1:0] noc_tx_tready;

    logic [3:0][7:0] noc_rx_tdata;
    logic [3:0][3:0] noc_rx_tdest;
    logic [3:0][1:0] noc_rx_tid;
    logic [3:0]      noc_rx_tlast;
    logic [3:0]      noc_rx_tvalid;
    logic [3:0][1:0] noc_rx_tready;

    noc_mesh_2x2_vc uut_noc (
        .clk        (clk_noc),
        .rst_n      (rst_n),
        .s_tdata    (noc_tx_tdata),
        .s_tdest    (noc_tx_tdest),
        .s_tid      (noc_tx_tid),
        .s_tlast    (noc_tx_tlast),
        .s_valid    (noc_tx_tvalid),
        .s_ready    (noc_tx_tready),
        .m_tdata    (noc_rx_tdata),
        .m_tdest    (noc_rx_tdest),
        .m_tid      (noc_rx_tid),
        .m_tlast    (noc_rx_tlast),
        .m_valid    (noc_rx_tvalid),
        .m_ready    (noc_rx_tready)
    );

    gals_node_wrapper wrap_00 (
        .clk_noc(clk_noc), .clk_host(clk_h00), .rst_n(rst_n),
        .s_host_tdata(h00_tx_tdata), .s_host_tdest(h00_tx_tdest), .s_host_tid(h00_tx_tid),
        .s_host_tlast(h00_tx_tlast), .s_host_valid(h00_tx_tvalid), .s_host_ready(h00_tx_tready),
        .m_host_tdata(h00_rx_tdata), .m_host_tdest(h00_rx_tdest), .m_host_tid(h00_rx_tid),
        .m_host_tlast(h00_rx_tlast), .m_host_valid(h00_rx_tvalid), .m_host_ready(h00_rx_tready),
        .m_noc_tdata(noc_tx_tdata[0]), .m_noc_tdest(noc_tx_tdest[0]), .m_noc_tid(noc_tx_tid[0]),
        .m_noc_tlast(noc_tx_tlast[0]), .m_noc_valid(noc_tx_tvalid[0]), .m_noc_ready(noc_tx_tready[0]),
        .s_noc_tdata(noc_rx_tdata[0]), .s_noc_tdest(noc_rx_tdest[0]), .s_noc_tid(noc_rx_tid[0]),
        .s_noc_tlast(noc_rx_tlast[0]), .s_noc_valid(noc_rx_tvalid[0]), .s_noc_ready(noc_rx_tready[0])
    );

    gals_node_wrapper wrap_01 (
        .clk_noc(clk_noc), .clk_host(clk_h01), .rst_n(rst_n),
        .s_host_tdata(h01_tx_tdata), .s_host_tdest(h01_tx_tdest), .s_host_tid(h01_tx_tid),
        .s_host_tlast(h01_tx_tlast), .s_host_valid(h01_tx_tvalid), .s_host_ready(h01_tx_tready),
        .m_host_tdata(h01_rx_tdata), .m_host_tdest(h01_rx_tdest), .m_host_tid(h01_rx_tid),
        .m_host_tlast(h01_rx_tlast), .m_host_valid(h01_rx_tvalid), .m_host_ready(h01_rx_tready),
        .m_noc_tdata(noc_tx_tdata[1]), .m_noc_tdest(noc_tx_tdest[1]), .m_noc_tid(noc_tx_tid[1]),
        .m_noc_tlast(noc_tx_tlast[1]), .m_noc_valid(noc_tx_tvalid[1]), .m_noc_ready(noc_tx_tready[1]),
        .s_noc_tdata(noc_rx_tdata[1]), .s_noc_tdest(noc_rx_tdest[1]), .s_noc_tid(noc_rx_tid[1]),
        .s_noc_tlast(noc_rx_tlast[1]), .s_noc_valid(noc_rx_tvalid[1]), .s_noc_ready(noc_rx_tready[1])
    );

    gals_node_wrapper wrap_10 (
        .clk_noc(clk_noc), .clk_host(clk_h10), .rst_n(rst_n),
        .s_host_tdata(h10_tx_tdata), .s_host_tdest(h10_tx_tdest), .s_host_tid(h10_tx_tid),
        .s_host_tlast(h10_tx_tlast), .s_host_valid(h10_tx_tvalid), .s_host_ready(h10_tx_tready),
        .m_host_tdata(h10_rx_tdata), .m_host_tdest(h10_rx_tdest), .m_host_tid(h10_rx_tid),
        .m_host_tlast(h10_rx_tlast), .m_host_valid(h10_rx_tvalid), .m_host_ready(h10_rx_tready),
        .m_noc_tdata(noc_tx_tdata[2]), .m_noc_tdest(noc_tx_tdest[2]), .m_noc_tid(noc_tx_tid[2]),
        .m_noc_tlast(noc_tx_tlast[2]), .m_noc_valid(noc_tx_tvalid[2]), .m_noc_ready(noc_tx_tready[2]),
        .s_noc_tdata(noc_rx_tdata[2]), .s_noc_tdest(noc_rx_tdest[2]), .s_noc_tid(noc_rx_tid[2]),
        .s_noc_tlast(noc_rx_tlast[2]), .s_noc_valid(noc_rx_tvalid[2]), .s_noc_ready(noc_rx_tready[2])
    );

    gals_node_wrapper wrap_11 (
        .clk_noc(clk_noc), .clk_host(clk_h11), .rst_n(rst_n),
        .s_host_tdata(h11_tx_tdata), .s_host_tdest(h11_tx_tdest), .s_host_tid(h11_tx_tid),
        .s_host_tlast(h11_tx_tlast), .s_host_valid(h11_tx_tvalid), .s_host_ready(h11_tx_tready),
        .m_host_tdata(h11_rx_tdata), .m_host_tdest(h11_rx_tdest), .m_host_tid(h11_rx_tid),
        .m_host_tlast(h11_rx_tlast), .m_host_valid(h11_rx_tvalid), .m_host_ready(h11_rx_tready),
        .m_noc_tdata(noc_tx_tdata[3]), .m_noc_tdest(noc_tx_tdest[3]), .m_noc_tid(noc_tx_tid[3]),
        .m_noc_tlast(noc_tx_tlast[3]), .m_noc_valid(noc_tx_tvalid[3]), .m_noc_ready(noc_tx_tready[3]),
        .s_noc_tdata(noc_rx_tdata[3]), .s_noc_tdest(noc_rx_tdest[3]), .s_noc_tid(noc_rx_tid[3]),
        .s_noc_tlast(noc_rx_tlast[3]), .s_noc_valid(noc_rx_tvalid[3]), .s_noc_ready(noc_rx_tready[3])
    );

endmodule
`timescale 1ns / 1ps

module gals_node_wrapper #(
    parameter DATA_W = 8,
    parameter CORD_W = 2,
    parameter DEPTH = 16,
    parameter NUM_VCS = 2
)(
    input  logic rst_n,

    input  logic clk_host,
    input  logic              s_host_valid,
    input  logic              s_host_tlast,
    input  logic [3:0]        s_host_tdest,
    input  logic [DATA_W-1:0] s_host_tdata,
    input  logic [NUM_VCS-1:0]s_host_tid,
    output logic [NUM_VCS-1:0]s_host_ready,

    output logic              m_host_valid,
    output logic              m_host_tlast,
    output logic [3:0]        m_host_tdest,
    output logic [DATA_W-1:0] m_host_tdata,
    output logic [NUM_VCS-1:0]m_host_tid,
    input  logic [NUM_VCS-1:0]m_host_ready,

    input  logic clk_noc,
    output logic              m_noc_valid,
    output logic              m_noc_tlast,
    output logic [3:0]        m_noc_tdest,
    output logic [DATA_W-1:0] m_noc_tdata,
    output logic [NUM_VCS-1:0]m_noc_tid,
    input  logic [NUM_VCS-1:0]m_noc_ready,

    input  logic              s_noc_valid,
    input  logic              s_noc_tlast,
    input  logic [3:0]        s_noc_tdest,
    input  logic [DATA_W-1:0] s_noc_tdata,
    input  logic [NUM_VCS-1:0]s_noc_tid,
    output logic [NUM_VCS-1:0]s_noc_ready
);

    localparam PACK_W = 1 + 4 + DATA_W;
    localparam ADDR_W = $clog2(DEPTH);

    logic [PACK_W-1:0] tx_wdata, tx_rdata [NUM_VCS];
    logic tx_empty [NUM_VCS], tx_full [NUM_VCS];
    assign tx_wdata = {s_host_tlast, s_host_tdest, s_host_tdata};

    genvar v;
    generate
        for (v = 0; v < NUM_VCS; v++) begin : TX_VC
            async_fifo_fwft #(.DATA_WIDTH(PACK_W), .ADDR_WIDTH(ADDR_W)) tx_fifo (
                .wclk(clk_host), .wrst_n(rst_n),
                .w_en(s_host_valid && s_host_tid[v] && !tx_full[v]),
                .wdata(tx_wdata), .wfull(tx_full[v]),

                .rclk(clk_noc),  .rrst_n(rst_n),
                .r_en(m_noc_valid && m_noc_tid[v] && m_noc_ready[v]),
                .rdata(tx_rdata[v]), .rempty(tx_empty[v]),

                .almost_full(), .prog_full_thresh('0), .ecc_single_err(), .ecc_double_err()
            );
            assign s_host_ready[v] = ~tx_full[v];
        end
    endgenerate

    always_comb begin
        m_noc_valid = 1'b0; m_noc_tid = '0; m_noc_tlast = 1'b0; m_noc_tdest = '0; m_noc_tdata = '0;

        if (!tx_empty[1] && m_noc_ready[1]) begin
            m_noc_valid = 1'b1; m_noc_tid = 2'b10;
            {m_noc_tlast, m_noc_tdest, m_noc_tdata} = tx_rdata[1];
        end else if (!tx_empty[0] && m_noc_ready[0]) begin
            m_noc_valid = 1'b1; m_noc_tid = 2'b01;
            {m_noc_tlast, m_noc_tdest, m_noc_tdata} = tx_rdata[0];
        end
    end

    logic [PACK_W-1:0] rx_wdata, rx_rdata [NUM_VCS];
    logic rx_empty [NUM_VCS], rx_full [NUM_VCS];
    assign rx_wdata = {s_noc_tlast, s_noc_tdest, s_noc_tdata};

    generate
        for (v = 0; v < NUM_VCS; v++) begin : RX_VC
            async_fifo_fwft #(.DATA_WIDTH(PACK_W), .ADDR_WIDTH(ADDR_W)) rx_fifo (
                .wclk(clk_noc), .wrst_n(rst_n),
                .w_en(s_noc_valid && s_noc_tid[v] && !rx_full[v]),
                .wdata(rx_wdata), .wfull(rx_full[v]),

                .rclk(clk_host), .rrst_n(rst_n),
                .r_en(m_host_valid && m_host_tid[v] && m_host_ready[v]),
                .rdata(rx_rdata[v]), .rempty(rx_empty[v]),

                .almost_full(), .prog_full_thresh('0), .ecc_single_err(), .ecc_double_err()
            );
            assign s_noc_ready[v] = ~rx_full[v];
        end
    endgenerate

    always_comb begin
        m_host_valid = 1'b0; m_host_tid = '0; m_host_tlast = 1'b0; m_host_tdest = '0; m_host_tdata = '0;

        if (!rx_empty[1] && m_host_ready[1]) begin
            m_host_valid = 1'b1; m_host_tid = 2'b10;
            {m_host_tlast, m_host_tdest, m_host_tdata} = rx_rdata[1];
        end else if (!rx_empty[0] && m_host_ready[0]) begin
            m_host_valid = 1'b1; m_host_tid = 2'b01;
            {m_host_tlast, m_host_tdest, m_host_tdata} = rx_rdata[0];
        end
    end

endmodule

`timescale 1ns / 1ps

module gray_counter #(
    parameter ADDR_WIDTH = 4
)(
    input  logic                  clk,
    input  logic                  rst,
    input  logic                  en,
    output logic [ADDR_WIDTH:0]   ptr_g,
    output logic [ADDR_WIDTH-1:0] addr
);

    logic [ADDR_WIDTH:0] bin;
    logic [ADDR_WIDTH:0] bin_next;
    logic [ADDR_WIDTH:0] gray_next;

    assign bin_next = bin + en;
    assign gray_next = bin_next ^ (bin_next >> 1);
    assign addr = bin[ADDR_WIDTH-1:0];

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            bin <= 0;
            ptr_g <= 0;
        end else begin
            bin <= bin_next;
            ptr_g <= gray_next;
        end
    end

    `ifdef FORMAL
        `ifndef FORMAL_TOP_INTEGRATION

        reg f_past_valid = 1'b0;
        reg f_past_en;
        reg [ADDR_WIDTH:0] f_past_bin;
        reg [ADDR_WIDTH:0] f_past_ptr_g;
        reg f_past_rst;

        always @(posedge clk) begin
            f_past_valid <= 1'b1;
            f_past_en <= en;
            f_past_bin <= bin;
            f_past_ptr_g <= ptr_g;
            f_past_rst <= rst;
        end

        reg f_async_reset_hit = 1'b0;
        always @(posedge clk or posedge rst) begin
            if (rst)
                f_async_reset_hit <= 1'b1;
            else
                f_async_reset_hit <= 1'b0;
        end

        always @(posedge clk) begin

            if (!f_past_valid) begin
                assume(rst);
            end

            if (rst) begin
                assert(bin == 0);
                assert(ptr_g == 0);
            end else begin

                assert(ptr_g == (bin ^ (bin >> 1)));
            end

            if (f_past_valid && !rst && !f_past_rst && !f_async_reset_hit) begin
                if (f_past_en) begin
                    assert($onehot(ptr_g ^ f_past_ptr_g));
                end else begin
                    assert(ptr_g == f_past_ptr_g);
                end

                if (bin[ADDR_WIDTH] != f_past_bin[ADDR_WIDTH]) begin
                    assert(ptr_g[ADDR_WIDTH] != f_past_ptr_g[ADDR_WIDTH]);
                end
            end
        end

        always @(posedge clk) begin
            if (f_past_valid && !rst && !f_past_rst && !f_async_reset_hit) begin
                cover (ptr_g == 0 && f_past_ptr_g != 0);
            end
        end
        `endif
    `endif

endmodule

`timescale 1ns / 1ps

module loopback_node_agent #(
    parameter [3:0] RETURN_DEST = 4'b0000
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

    logic busy;
    logic current_tx_ready;

    assign current_tx_ready = (tx_tid[1] & tx_tready[1]) | (tx_tid[0] & tx_tready[0]);

    assign rx_tready = busy ? 2'b00 : 2'b11;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy      <= 1'b0;
            tx_tvalid <= 1'b0;
            tx_tdata  <= '0;
            tx_tdest  <= '0;
            tx_tid    <= '0;
            tx_tlast  <= 1'b0;
        end else begin
            if (busy) begin

                if (current_tx_ready && tx_tvalid) begin
                    busy      <= 1'b0;
                    tx_tvalid <= 1'b0;
                end
            end else if (rx_tvalid) begin

                busy      <= 1'b1;
                tx_tvalid <= 1'b1;
                tx_tdata  <= rx_tdata;
                tx_tlast  <= rx_tlast;
                tx_tid    <= rx_tid;
                tx_tdest  <= RETURN_DEST;
            end
        end
    end

endmodule
`timescale 1ns / 1ps

module noc_mesh_2x2_vc #(
    parameter DATA_W = 8,
    parameter CORD_W = 2,
    parameter NUM_VCS = 2,
    parameter DEPTH = 16
)(
    input  logic clk,
    input  logic rst_n,

    input  logic [3:0]              s_valid,
    input  logic [3:0]              s_tlast,
    input  logic [3:0][3:0]         s_tdest,
    input  logic [3:0][DATA_W-1:0]  s_tdata,
    input  logic [3:0][NUM_VCS-1:0] s_tid,
    output logic [3:0][NUM_VCS-1:0] s_ready,

    output logic [3:0]              m_valid,
    output logic [3:0]              m_tlast,
    output logic [3:0][3:0]         m_tdest,
    output logic [3:0][DATA_W-1:0]  m_tdata,
    output logic [3:0][NUM_VCS-1:0] m_tid,
    input  logic [3:0][NUM_VCS-1:0] m_ready
);

    localparam LOCAL = 0, NORTH = 1, SOUTH = 2, EAST = 3, WEST = 4;

    logic [4:0]              r_valid [4];
    logic [4:0]              r_last  [4];
    logic [4:0][3:0]         r_dst   [4];
    logic [4:0][DATA_W-1:0]  r_dat   [4];
    logic [4:0][NUM_VCS-1:0] r_tid   [4];
    logic [4:0][NUM_VCS-1:0] r_rdy   [4];

    logic [4:0]              m_valid_wire [4];
    logic [4:0]              m_last_wire  [4];
    logic [4:0][3:0]         m_dst_wire   [4];
    logic [4:0][DATA_W-1:0]  m_dat_wire   [4];
    logic [4:0][NUM_VCS-1:0] m_tid_wire   [4];
    logic [4:0][NUM_VCS-1:0] m_rdy_wire   [4];

    genvar x, y;
    generate
        for (y = 0; y < 2; y++) begin : ROW
            for (x = 0; x < 2; x++) begin : COL
                localparam int idx = y * 2 + x;

                router_5port_mesh_vc #(
                    .MY_X(x), .MY_Y(y), .DATA_W(DATA_W), .CORD_W(CORD_W), .NUM_VCS(NUM_VCS), .DEPTH(DEPTH)
                ) router (
                    .clk(clk), .rst_n(rst_n),
                    .s_valid(r_valid[idx]), .s_tlast(r_last[idx]), .s_tdest(r_dst[idx]), .s_tdata(r_dat[idx]), .s_tid(r_tid[idx]), .s_ready(r_rdy[idx]),
                    .m_valid(m_valid_wire[idx]), .m_tlast(m_last_wire[idx]), .m_tdest(m_dst_wire[idx]), .m_tdata(m_dat_wire[idx]), .m_tid(m_tid_wire[idx]), .m_ready(m_rdy_wire[idx])
                );
            end
        end
    endgenerate

    generate
        for (genvar i = 0; i < 4; i++) begin : LOCAL_PORTS

            assign r_valid[i][LOCAL] = s_valid[i];
            assign r_last[i][LOCAL]  = s_tlast[i];
            assign r_dst[i][LOCAL]   = s_tdest[i];
            assign r_dat[i][LOCAL]   = s_tdata[i];
            assign r_tid[i][LOCAL]   = s_tid[i];
            assign s_ready[i]        = r_rdy[i][LOCAL];

            assign m_valid[i] = m_valid_wire[i][LOCAL];
            assign m_tlast[i] = m_last_wire[i][LOCAL];
            assign m_tdest[i] = m_dst_wire[i][LOCAL];
            assign m_tdata[i] = m_dat_wire[i][LOCAL];
            assign m_tid[i]   = m_tid_wire[i][LOCAL];
            assign m_rdy_wire[i][LOCAL] = m_ready[i];
        end
    endgenerate

    assign r_valid[1][WEST] = m_valid_wire[0][EAST];
    assign r_last[1][WEST]  = m_last_wire[0][EAST];
    assign r_dst[1][WEST]   = m_dst_wire[0][EAST];
    assign r_dat[1][WEST]   = m_dat_wire[0][EAST];
    assign r_tid[1][WEST]   = m_tid_wire[0][EAST];
    assign m_rdy_wire[0][EAST] = r_rdy[1][WEST];

    assign r_valid[0][EAST] = m_valid_wire[1][WEST];
    assign r_last[0][EAST]  = m_last_wire[1][WEST];
    assign r_dst[0][EAST]   = m_dst_wire[1][WEST];
    assign r_dat[0][EAST]   = m_dat_wire[1][WEST];
    assign r_tid[0][EAST]   = m_tid_wire[1][WEST];
    assign m_rdy_wire[1][WEST] = r_rdy[0][EAST];

    assign r_valid[3][WEST] = m_valid_wire[2][EAST];
    assign r_last[3][WEST]  = m_last_wire[2][EAST];
    assign r_dst[3][WEST]   = m_dst_wire[2][EAST];
    assign r_dat[3][WEST]   = m_dat_wire[2][EAST];
    assign r_tid[3][WEST]   = m_tid_wire[2][EAST];
    assign m_rdy_wire[2][EAST] = r_rdy[3][WEST];

    assign r_valid[2][EAST] = m_valid_wire[3][WEST];
    assign r_last[2][EAST]  = m_last_wire[3][WEST];
    assign r_dst[2][EAST]   = m_dst_wire[3][WEST];
    assign r_dat[2][EAST]   = m_dat_wire[3][WEST];
    assign r_tid[2][EAST]   = m_tid_wire[3][WEST];
    assign m_rdy_wire[3][WEST] = r_rdy[2][EAST];

    assign r_valid[2][SOUTH] = m_valid_wire[0][NORTH];
    assign r_last[2][SOUTH]  = m_last_wire[0][NORTH];
    assign r_dst[2][SOUTH]   = m_dst_wire[0][NORTH];
    assign r_dat[2][SOUTH]   = m_dat_wire[0][NORTH];
    assign r_tid[2][SOUTH]   = m_tid_wire[0][NORTH];
    assign m_rdy_wire[0][NORTH] = r_rdy[2][SOUTH];

    assign r_valid[0][NORTH] = m_valid_wire[2][SOUTH];
    assign r_last[0][NORTH]  = m_last_wire[2][SOUTH];
    assign r_dst[0][NORTH]   = m_dst_wire[2][SOUTH];
    assign r_dat[0][NORTH]   = m_dat_wire[2][SOUTH];
    assign r_tid[0][NORTH]   = m_tid_wire[2][SOUTH];
    assign m_rdy_wire[2][SOUTH] = r_rdy[0][NORTH];

    assign r_valid[3][SOUTH] = m_valid_wire[1][NORTH];
    assign r_last[3][SOUTH]  = m_last_wire[1][NORTH];
    assign r_dst[3][SOUTH]   = m_dst_wire[1][NORTH];
    assign r_dat[3][SOUTH]   = m_dat_wire[1][NORTH];
    assign r_tid[3][SOUTH]   = m_tid_wire[1][NORTH];
    assign m_rdy_wire[1][NORTH] = r_rdy[3][SOUTH];

    assign r_valid[1][NORTH] = m_valid_wire[3][SOUTH];
    assign r_last[1][NORTH]  = m_last_wire[3][SOUTH];
    assign r_dst[1][NORTH]   = m_dst_wire[3][SOUTH];
    assign r_dat[1][NORTH]   = m_dat_wire[3][SOUTH];
    assign r_tid[1][NORTH]   = m_tid_wire[3][SOUTH];
    assign m_rdy_wire[3][SOUTH] = r_rdy[1][NORTH];

    assign r_valid[0][SOUTH] = 1'b0; assign m_rdy_wire[0][SOUTH] = '0;
    assign r_valid[0][WEST]  = 1'b0; assign m_rdy_wire[0][WEST]  = '0;

    assign r_valid[1][SOUTH] = 1'b0; assign m_rdy_wire[1][SOUTH] = '0;
    assign r_valid[1][EAST]  = 1'b0; assign m_rdy_wire[1][EAST]  = '0;

    assign r_valid[2][NORTH] = 1'b0; assign m_rdy_wire[2][NORTH] = '0;
    assign r_valid[2][WEST]  = 1'b0; assign m_rdy_wire[2][WEST]  = '0;

    assign r_valid[3][NORTH] = 1'b0; assign m_rdy_wire[3][NORTH] = '0;
    assign r_valid[3][EAST]  = 1'b0; assign m_rdy_wire[3][EAST]  = '0;

    assign r_valid[0][SOUTH] = 1'b0; assign m_rdy_wire[0][SOUTH] = '0;
    assign r_last[0][SOUTH]  = 1'b0; assign r_dst[0][SOUTH] = '0; assign r_dat[0][SOUTH] = '0; assign r_tid[0][SOUTH] = '0;
    assign r_valid[0][WEST]  = 1'b0; assign m_rdy_wire[0][WEST]  = '0;
    assign r_last[0][WEST]   = 1'b0; assign r_dst[0][WEST]  = '0; assign r_dat[0][WEST]  = '0; assign r_tid[0][WEST]  = '0;

    assign r_valid[1][SOUTH] = 1'b0; assign m_rdy_wire[1][SOUTH] = '0;
    assign r_last[1][SOUTH]  = 1'b0; assign r_dst[1][SOUTH] = '0; assign r_dat[1][SOUTH] = '0; assign r_tid[1][SOUTH] = '0;
    assign r_valid[1][EAST]  = 1'b0; assign m_rdy_wire[1][EAST]  = '0;
    assign r_last[1][EAST]   = 1'b0; assign r_dst[1][EAST]  = '0; assign r_dat[1][EAST]  = '0; assign r_tid[1][EAST]  = '0;

    assign r_valid[2][NORTH] = 1'b0; assign m_rdy_wire[2][NORTH] = '0;
    assign r_last[2][NORTH]  = 1'b0; assign r_dst[2][NORTH] = '0; assign r_dat[2][NORTH] = '0; assign r_tid[2][NORTH] = '0;
    assign r_valid[2][WEST]  = 1'b0; assign m_rdy_wire[2][WEST]  = '0;
    assign r_last[2][WEST]   = 1'b0; assign r_dst[2][WEST]  = '0; assign r_dat[2][WEST]  = '0; assign r_tid[2][WEST]  = '0;

    assign r_valid[3][NORTH] = 1'b0; assign m_rdy_wire[3][NORTH] = '0;
    assign r_last[3][NORTH]  = 1'b0; assign r_dst[3][NORTH] = '0; assign r_dat[3][NORTH] = '0; assign r_tid[3][NORTH] = '0;
    assign r_valid[3][EAST]  = 1'b0; assign m_rdy_wire[3][EAST]  = '0;
    assign r_last[3][EAST]   = 1'b0; assign r_dst[3][EAST]  = '0; assign r_dat[3][EAST]  = '0; assign r_tid[3][EAST]  = '0;

endmodule

`timescale 1ns / 1ps

module traffic_node_agent #(
    parameter [3:0] DEST_ID = 4'b0000,
    parameter [7:0] PAYLOAD = 8'hAA,

    parameter int   INTERVAL = 10000000
)(
    input  logic clk,
    input  logic rst_n,

    output logic [7:0] tx_tdata,
    output logic [3:0] tx_tdest,
    output logic       tx_tvalid,
    input  logic [1:0] tx_tready,

    input  logic [7:0] rx_tdata,
    input  logic       rx_tvalid,
    output logic [1:0] rx_tready,

    output logic       pass,
    output logic       fail
);

    logic [31:0] delay_cnt;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_tvalid <= 1'b0;
            tx_tdata  <= PAYLOAD;
            tx_tdest  <= DEST_ID;
            delay_cnt <= 0;
        end else begin

            if (delay_cnt < INTERVAL) begin
                tx_tvalid <= 1'b0;
                delay_cnt <= delay_cnt + 1;
            end else begin
                tx_tvalid <= 1'b1;

                if (tx_tvalid && tx_tready[0]) begin
                    delay_cnt <= 0;
                    tx_tvalid <= 1'b0;
                end
            end
        end
    end

    assign rx_tready = 2'b11;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pass <= 1'b0;
            fail <= 1'b0;
        end else begin
            if (rx_tvalid) begin

                if (rx_tdata != ~PAYLOAD) begin
                    fail <= 1'b1;
                end else begin
                    pass <= 1'b1;
                end
            end
        end
    end
endmodule

module noc_stress_tester (
    input logic clk_h00, input logic clk_h01,
    input logic clk_h10, input logic clk_h11,
    input logic rst_n,

    output logic [7:0] t00_tx_data, output logic [3:0] t00_tx_dest, output logic t00_tx_valid, input logic [1:0] t00_tx_ready,
    input  logic [7:0] t00_rx_data, input  logic t00_rx_valid, output logic [1:0] t00_rx_ready,

    output logic [7:0] t01_tx_data, output logic [3:0] t01_tx_dest, output logic t01_tx_valid, input logic [1:0] t01_tx_ready,
    input  logic [7:0] t01_rx_data, input  logic t01_rx_valid, output logic [1:0] t01_rx_ready,

    output logic [7:0] t10_tx_data, output logic [3:0] t10_tx_dest, output logic t10_tx_valid, input logic [1:0] t10_tx_ready,
    input  logic [7:0] t10_rx_data, input  logic t10_rx_valid, output logic [1:0] t10_rx_ready,

    output logic [7:0] t11_tx_data, output logic [3:0] t11_tx_dest, output logic t11_tx_valid, input logic [1:0] t11_tx_ready,
    input  logic [7:0] t11_rx_data, input  logic t11_rx_valid, output logic [1:0] t11_rx_ready,

    output logic pass_group1,
    output logic pass_group2,
    output logic any_fail
);
    logic p00, f00, p01, f01, p10, f10, p11, f11;

    traffic_node_agent #(.DEST_ID(4'b0101), .PAYLOAD(8'hAA)) agent_00 (
        .clk(clk_h00), .rst_n(rst_n),
        .tx_tdata(t00_tx_data), .tx_tdest(t00_tx_dest), .tx_tvalid(t00_tx_valid), .tx_tready(t00_tx_ready),
        .rx_tdata(t00_rx_data), .rx_tvalid(t00_rx_valid), .rx_tready(t00_rx_ready), .pass(p00), .fail(f00)
    );

    traffic_node_agent #(.DEST_ID(4'b0000), .PAYLOAD(8'h55)) agent_11 (
        .clk(clk_h11), .rst_n(rst_n),
        .tx_tdata(t11_tx_data), .tx_tdest(t11_tx_dest), .tx_tvalid(t11_tx_valid), .tx_tready(t11_tx_ready),
        .rx_tdata(t11_rx_data), .rx_tvalid(t11_rx_valid), .rx_tready(t11_rx_ready), .pass(p11), .fail(f11)
    );

    traffic_node_agent #(.DEST_ID(4'b0001), .PAYLOAD(8'hCC)) agent_01 (
        .clk(clk_h01), .rst_n(rst_n),
        .tx_tdata(t01_tx_data), .tx_tdest(t01_tx_dest), .tx_tvalid(t01_tx_valid), .tx_tready(t01_tx_ready),
        .rx_tdata(t01_rx_data), .rx_tvalid(t01_rx_valid), .rx_tready(t01_rx_ready), .pass(p01), .fail(f01)
    );

    traffic_node_agent #(.DEST_ID(4'b0100), .PAYLOAD(8'h33)) agent_10 (
        .clk(clk_h10), .rst_n(rst_n),
        .tx_tdata(t10_tx_data), .tx_tdest(t10_tx_dest), .tx_tvalid(t10_tx_valid), .tx_tready(t10_tx_ready),
        .rx_tdata(t10_rx_data), .rx_tvalid(t10_rx_valid), .rx_tready(t10_rx_ready), .pass(p10), .fail(f10)
    );

    assign pass_group1 = p00 & p11;
    assign pass_group2 = p01 & p10;
    assign any_fail    = f00 | f01 | f10 | f11;

endmodule
`timescale 1ns / 1ps

module packet_arbiter #(
    parameter PORTS = 4
)(
    input  logic             clk,
    input  logic             rst_n,

    input  logic [PORTS-1:0] valid,
    input  logic [PORTS-1:0] tlast,
    input  logic             ready,

    output logic [PORTS-1:0] grant
);

    typedef enum logic {IDLE, LOCKED} state_t;
    state_t state;

    logic [PORTS-1:0] locked_grant;
    logic [PORTS-1:0] mask;
    logic             locked_from_mask;

    logic [PORTS-1:0] masked_req;
    logic [PORTS-1:0] masked_grant;
    logic [PORTS-1:0] unmasked_grant;
    logic [PORTS-1:0] next_grant;

    assign masked_req     = valid & mask;
    assign masked_grant   = masked_req & (~masked_req + 1'b1);
    assign unmasked_grant = valid & (~valid + 1'b1);

    assign next_grant     = (masked_req != '0) ? masked_grant : unmasked_grant;

    logic eop_transfer;
    assign eop_transfer = |(grant & valid & tlast) && ready;

    assign grant = (state == LOCKED) ? locked_grant : (|valid ? next_grant : '0);

    logic current_from_mask;
    assign current_from_mask = (state == LOCKED) ? locked_from_mask : (masked_req != '0);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= IDLE;
            locked_grant     <= '0;
            locked_from_mask <= 1'b0;
            mask             <= {PORTS{1'b1}};
        end else begin

            case (state)
                IDLE: begin
                    if (|valid) begin
                        if (!(ready && |(next_grant & tlast))) begin
                            state            <= LOCKED;
                            locked_grant     <= next_grant;
                            locked_from_mask <= (masked_req != '0);
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

            if (eop_transfer) begin
                if (current_from_mask || mask == '0) begin

                    mask <= (~(grant | (grant - 1'b1)) == '0) ? {PORTS{1'b1}} : ~(grant | (grant - 1'b1));
                end
            end
        end
    end

    `ifdef FORMAL
        reg f_past_valid = 1'b0;
        always @(posedge clk) f_past_valid <= 1'b1;

        always @(*) begin
            if (!f_past_valid) assume(!rst_n);
            if (rst_n && f_past_valid) begin
                if (grant != '0) begin
                    assert_onehot: assert($onehot(grant));
                end
            end
        end

        always @(posedge clk) begin
            if (f_past_valid && $past(rst_n) && rst_n) begin
                if ($past(state) == LOCKED && !$past(eop_transfer)) begin
                    assert_channel_lock: assert(grant == $past(grant));
                end
            end
        end
    `endif

endmodule

`timescale 1ns / 1ps

module router_5port_mesh_vc #(
    parameter [1:0] MY_X = 2'd0,
    parameter [1:0] MY_Y = 2'd0,
    parameter DATA_W = 8,
    parameter CORD_W = 2,
    parameter NUM_VCS = 2,
    parameter DEPTH = 16
)(
    input  logic clk,
    input  logic rst_n,

    input  logic [4:0]              s_valid,
    input  logic [4:0]              s_tlast,
    input  logic [4:0][3:0]         s_tdest,
    input  logic [4:0][DATA_W-1:0]  s_tdata,
    input  logic [4:0][NUM_VCS-1:0] s_tid,
    output logic [4:0][NUM_VCS-1:0] s_ready,

    output logic [4:0]              m_valid,
    output logic [4:0]              m_tlast,
    output logic [4:0][3:0]         m_tdest,
    output logic [4:0][DATA_W-1:0]  m_tdata,
    output logic [4:0][NUM_VCS-1:0] m_tid,
    input  logic [4:0][NUM_VCS-1:0] m_ready
);

    localparam LOCAL = 0, NORTH = 1, SOUTH = 2, EAST = 3, WEST = 4;

    logic              buf_valid [5][NUM_VCS];
    logic              buf_tlast [5][NUM_VCS];
    logic [3:0]        buf_tdest [5][NUM_VCS];
    logic [DATA_W-1:0] buf_tdata [5][NUM_VCS];
    logic              buf_ready [5][NUM_VCS];

    generate
        for (genvar p = 0; p < 5; p++) begin : GEN_IN_BUF
            vc_input_buffer #(
                .DATA_W(DATA_W), .CORD_W(CORD_W), .NUM_VCS(NUM_VCS), .DEPTH(DEPTH)
            ) in_buf (
                .clk(clk), .rst_n(rst_n),
                .s_valid(s_valid[p]), .s_tlast(s_tlast[p]), .s_tdest(s_tdest[p]), .s_tdata(s_tdata[p]), .s_tid(s_tid[p]), .s_ready(s_ready[p]),
                .m_valid(buf_valid[p]), .m_tlast(buf_tlast[p]), .m_tdest(buf_tdest[p]), .m_tdata(buf_tdata[p]), .m_ready(buf_ready[p])
            );
        end
    endgenerate

    logic [4:0] route_req [5][NUM_VCS];

    always_comb begin
        for (int in_p = 0; in_p < 5; in_p++) begin
            for (int vc = 0; vc < NUM_VCS; vc++) begin
                route_req[in_p][vc] = '0;
                if (buf_valid[in_p][vc]) begin
                    automatic logic [1:0] dx = buf_tdest[in_p][vc][3:2];
                    automatic logic [1:0] dy = buf_tdest[in_p][vc][1:0];

                    if      (dx > MY_X) route_req[in_p][vc][EAST]  = 1'b1;
                    else if (dx < MY_X) route_req[in_p][vc][WEST]  = 1'b1;
                    else if (dy > MY_Y) route_req[in_p][vc][NORTH] = 1'b1;
                    else if (dy < MY_Y) route_req[in_p][vc][SOUTH] = 1'b1;
                    else                route_req[in_p][vc][LOCAL] = 1'b1;
                end
            end
        end
    end

    logic [4:0] req_out_vc0 [5];
    logic [4:0] req_out_vc1 [5];
    logic [4:0] last_out_vc0 [5];
    logic [4:0] last_out_vc1 [5];

    logic [4:0] grant_vc0 [5];
    logic [4:0] grant_vc1 [5];
    logic       ready_from_arb_vc0 [5];
    logic       ready_from_arb_vc1 [5];

    always_comb begin
        for (int out_p = 0; out_p < 5; out_p++) begin
            for (int in_p = 0; in_p < 5; in_p++) begin
                req_out_vc0[out_p][in_p]  = route_req[in_p][0][out_p];
                req_out_vc1[out_p][in_p]  = route_req[in_p][1][out_p];
                last_out_vc0[out_p][in_p] = buf_tlast[in_p][0];
                last_out_vc1[out_p][in_p] = buf_tlast[in_p][1];
            end
        end
    end

    generate
        for (genvar out_p = 0; out_p < 5; out_p++) begin : GEN_ARB
            vc_port_arbiter #(
                .PORTS(5)
            ) arb_inst (
                .clk(clk),
                .rst_n(rst_n),

                .valid_vc1(req_out_vc1[out_p]),
                .tlast_vc1(last_out_vc1[out_p]),
                .grant_vc1(grant_vc1[out_p]),

                .valid_vc0(req_out_vc0[out_p]),
                .tlast_vc0(last_out_vc0[out_p]),
                .grant_vc0(grant_vc0[out_p]),

                .ready_out_vc1(m_ready[out_p][1]),
                .ready_out_vc0(m_ready[out_p][0]),

                .ready_vc1(ready_from_arb_vc1[out_p]),
                .ready_vc0(ready_from_arb_vc0[out_p])
            );
        end
    endgenerate

    always_comb begin
        for (int out_p = 0; out_p < 5; out_p++) begin

            m_valid[out_p] = 1'b0;
            m_tlast[out_p] = 1'b0;
            m_tdest[out_p] = '0;
            m_tdata[out_p] = '0;
            m_tid[out_p]   = '0;

            for (int in_p = 0; in_p < 5; in_p++) begin

                m_valid[out_p] |= (buf_valid[in_p][1] & grant_vc1[out_p][in_p]);
                m_tlast[out_p] |= (buf_tlast[in_p][1] & grant_vc1[out_p][in_p]);
                m_tdest[out_p] |= (buf_tdest[in_p][1] & {4{grant_vc1[out_p][in_p]}});
                m_tdata[out_p] |= (buf_tdata[in_p][1] & {DATA_W{grant_vc1[out_p][in_p]}});

                m_valid[out_p] |= (buf_valid[in_p][0] & grant_vc0[out_p][in_p]);
                m_tlast[out_p] |= (buf_tlast[in_p][0] & grant_vc0[out_p][in_p]);
                m_tdest[out_p] |= (buf_tdest[in_p][0] & {4{grant_vc0[out_p][in_p]}});
                m_tdata[out_p] |= (buf_tdata[in_p][0] & {DATA_W{grant_vc0[out_p][in_p]}});
            end

            m_tid[out_p] = (2'b10 & {2{|grant_vc1[out_p]}}) |
                           (2'b01 & {2{|grant_vc0[out_p]}});
        end
    end

    always_comb begin
        for (int in_p = 0; in_p < 5; in_p++) begin
            buf_ready[in_p][0] = 1'b0;
            buf_ready[in_p][1] = 1'b0;
            for (int out_p = 0; out_p < 5; out_p++) begin
                if (grant_vc0[out_p][in_p]) buf_ready[in_p][0] |= ready_from_arb_vc0[out_p];
                if (grant_vc1[out_p][in_p]) buf_ready[in_p][1] |= ready_from_arb_vc1[out_p];
            end
        end
    end

endmodule
`timescale 1ns / 1ps

module sync_2stage #(
    parameter WIDTH = 5
)(
    input logic clk,
    input logic rst,
    input logic [WIDTH-1:0] d,
    (* ASYNC_REG = "TRUE" *) output logic [WIDTH-1:0] q
    );

    (* ASYNC_REG = "TRUE" *) logic [WIDTH-1:0] q1;

    always_ff @(posedge clk or posedge rst) begin
        if(rst) begin
            q1 <= '0;
            q <= '0;
        end else begin
            q1 <= d;
            q <= q1;
        end
    end

    `ifdef FORMAL
        `ifndef FORMAL_TOP_INTEGRATION

        reg f_past_valid = 1'b0;
        reg [WIDTH-1:0] f_past_q1;
        reg f_past_rst;

        always @(posedge clk) begin
            f_past_valid <= 1'b1;
            f_past_q1 <= q1;
            f_past_rst <= rst;
        end

        reg f_async_reset_hit = 1'b0;
        always @(posedge clk or posedge rst) begin
            if (rst)
                f_async_reset_hit <= 1'b1;
            else
                f_async_reset_hit <= 1'b0;
        end

        always @(posedge clk) begin

            if (!f_past_valid) begin
                assume(rst);
            end

            if (rst) begin
                assert(q1 == 0);
                assert(q == 0);
            end

            else if (f_past_valid && !f_past_rst && !f_async_reset_hit) begin
                assert_stage2: assert (q == f_past_q1);
            end
        end

        always @(posedge clk) begin
            if (f_past_valid && !rst && !f_async_reset_hit) begin
                cover_data_pass: cover (q != 0);
            end
        end
        `endif
    `endif

endmodule

`timescale 1ns / 1ps

module sync_fifo #(
    parameter DATA_WIDTH = 8,
    parameter DEPTH = 16
)(
    input  logic clk,
    input  logic rst_n,

    input  logic w_en,
    input  logic [DATA_WIDTH-1:0] w_data,

    input  logic r_en,
    output logic [DATA_WIDTH-1:0] r_data,

    output logic full,
    output logic empty
);

    localparam ADDR_W = $clog2(DEPTH);

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    logic [ADDR_W:0] w_ptr, r_ptr;

    logic is_empty;
    assign is_empty = (w_ptr == r_ptr);
    assign full     = (w_ptr[ADDR_W] != r_ptr[ADDR_W]) && (w_ptr[ADDR_W-1:0] == r_ptr[ADDR_W-1:0]);

    assign r_data = mem[r_ptr[ADDR_W-1:0]];
    assign empty  = is_empty;

    always_ff @(posedge clk) begin
        if (w_en && !full) begin
            mem[w_ptr[ADDR_W-1:0]] <= w_data;
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_ptr <= '0;
            r_ptr <= '0;
        end else begin

            if (w_en && !full) begin
                w_ptr <= w_ptr + 1'b1;
            end

            if (r_en && !is_empty) begin
                r_ptr <= r_ptr + 1'b1;
            end
        end
    end

endmodule

`timescale 1ns / 1ps

module traffic_gen #(
    parameter [3:0] MY_ID = 4'h0,
    parameter NUM_VCS = 2
)(
    input  logic clk,
    input  logic rst_n,

    input  logic start,
    input  logic [1:0] target_x,
    input  logic [1:0] target_y,
    input  logic [7:0] pkt_len,
    input  logic [NUM_VCS-1:0] pkt_tid,

    output logic ready_out,

    output logic m_axis_tvalid,
    output logic [7:0] m_axis_tdata,
    output logic [3:0] m_axis_tdest,
    output logic m_axis_tlast,
    output logic [NUM_VCS-1:0] m_axis_tid,
    input  logic [NUM_VCS-1:0] m_axis_tready
);

    typedef enum logic [1:0] {IDLE, SEND} state_t;
    state_t state, next_state;

    logic [7:0] flit_cnt, next_flit_cnt;
    logic [7:0] data_reg, next_data_reg;

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
                latch_tid <= pkt_tid;
            end
        end
    end

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

                if (current_vc_ready) begin
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
    assign m_axis_tid   = latch_tid;

endmodule

`timescale 1ns / 1ps

module uart_noc_host #(
    parameter CLK_FREQ = 100_000_000,
    parameter BAUD_RATE = 115200
)(
    input  logic clk,
    input  logic rst_n,

    input  logic uart_rxd,
    output logic uart_txd,

    output logic [7:0] tx_tdata,
    output logic [3:0] tx_tdest,
    output logic [1:0] tx_tid,
    output logic       tx_tlast,
    output logic       tx_tvalid,
    input  logic [1:0] tx_tready,

    input  logic [7:0] rx_tdata,
    input  logic [3:0] rx_tdest,
    input  logic [1:0] rx_tid,
    input  logic       rx_tlast,
    input  logic       rx_tvalid,
    output logic [1:0] rx_tready
);

    logic [7:0] uart_rx_data;
    logic       uart_rx_valid;

    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) rx_inst (
        .clk(clk), .rst(!rst_n), .rx(uart_rxd),
        .rx_data(uart_rx_data), .rx_valid(uart_rx_valid)
    );

    logic [7:0] uart_tx_data;
    logic       uart_tx_valid;
    logic       uart_tx_ready;

    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) tx_inst (
        .clk(clk), .rst(!rst_n),
        .tx_data(uart_tx_data), .tx_valid(uart_tx_valid),
        .tx(uart_txd), .tx_ready(uart_tx_ready)
    );

    logic [7:0] header_reg;
    enum logic [1:0] {P_WAIT_B1, P_WAIT_B2, P_PUSH_NOC} p_state;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            p_state   <= P_WAIT_B1;
            tx_tvalid <= 1'b0;
            tx_tdata  <= '0;
            tx_tdest  <= '0;
            tx_tid    <= '0;
            tx_tlast  <= 1'b0;
        end else begin
            case (p_state)
                P_WAIT_B1: begin
                    if (uart_rx_valid) begin
                        header_reg <= uart_rx_data;
                        p_state    <= P_WAIT_B2;
                    end
                end

                P_WAIT_B2: begin
                    if (uart_rx_valid) begin
                        tx_tdata  <= uart_rx_data;
                        tx_tdest  <= header_reg[3:0];
                        tx_tid    <= header_reg[6:5];
                        tx_tlast  <= header_reg[7];
                        tx_tvalid <= 1'b1;
                        p_state   <= P_PUSH_NOC;
                    end
                end

                P_PUSH_NOC: begin

                    logic vc_ready;
                    vc_ready = (tx_tid[1] & tx_tready[1]) | (tx_tid[0] & tx_tready[0]);

                    if (vc_ready) begin
                        tx_tvalid <= 1'b0;
                        p_state   <= P_WAIT_B1;
                    end
                end
            endcase
        end
    end

    enum logic [2:0] {
        D_IDLE,
        D_SEND_B1, D_WAIT_B1_BUSY, D_WAIT_B1_DONE,
        D_SEND_B2, D_WAIT_B2_BUSY, D_WAIT_B2_DONE
    } d_state;

    logic [7:0] noc_header_reg;
    logic [7:0] noc_data_reg;

    assign rx_tready = (d_state == D_IDLE) ? 2'b11 : 2'b00;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            d_state       <= D_IDLE;
            uart_tx_valid <= 1'b0;
            uart_tx_data  <= '0;
        end else begin
            case (d_state)
                D_IDLE: begin
                    if (rx_tvalid) begin

                        noc_header_reg <= {rx_tlast, rx_tid, 1'b0, rx_tdest};

                        noc_data_reg   <= rx_tdata;
                        d_state        <= D_SEND_B1;
                    end
                end

                D_SEND_B1: begin
                    if (uart_tx_ready) begin
                        uart_tx_data  <= noc_header_reg;
                        uart_tx_valid <= 1'b1;
                        d_state       <= D_WAIT_B1_BUSY;
                    end
                end
                D_WAIT_B1_BUSY: begin
                    uart_tx_valid <= 1'b0;
                    if (!uart_tx_ready) d_state <= D_WAIT_B1_DONE;
                end
                D_WAIT_B1_DONE: begin
                    if (uart_tx_ready) d_state <= D_SEND_B2;
                end

                D_SEND_B2: begin
                    if (uart_tx_ready) begin
                        uart_tx_data  <= noc_data_reg;
                        uart_tx_valid <= 1'b1;
                        d_state       <= D_WAIT_B2_BUSY;
                    end
                end
                D_WAIT_B2_BUSY: begin
                    uart_tx_valid <= 1'b0;
                    if (!uart_tx_ready) d_state <= D_WAIT_B2_DONE;
                end
                D_WAIT_B2_DONE: begin
                    if (uart_tx_ready) d_state <= D_IDLE;
                end
            endcase
        end
    end

endmodule
`timescale 1ns / 1ps

module uart_rx #(parameter CLK_FREQ = 100_000_000, BAUD_RATE = 115200) (
    input  logic clk, rst, rx,
    output logic [7:0] rx_data,
    output logic rx_valid
);
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    enum logic [1:0] {IDLE, START, DATA, STOP} state;
    logic [15:0] clk_cnt;
    logic [2:0]  bit_cnt;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE; rx_valid <= 0; rx_data <= 0;
            clk_cnt <= 0; bit_cnt <= 0;
        end else begin
            rx_valid <= 0;
            case (state)
                IDLE: begin
                    clk_cnt <= 0; bit_cnt <= 0;
                    if (rx == 0) state <= START;
                end
                START: begin
                    if (clk_cnt == CLKS_PER_BIT/2) begin
                        if (rx == 0) begin clk_cnt <= 0; state <= DATA; end
                        else state <= IDLE;
                    end else clk_cnt <= clk_cnt + 1;
                end
                DATA: begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= 0;
                        rx_data[bit_cnt] <= rx;
                        if (bit_cnt == 7) state <= STOP;
                        else bit_cnt <= bit_cnt + 1;
                    end else clk_cnt <= clk_cnt + 1;
                end
                STOP: begin
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        rx_valid <= 1;
                        state <= IDLE;
                    end else clk_cnt <= clk_cnt + 1;
                end
            endcase
        end
    end
endmodule

module uart_tx #(parameter CLK_FREQ = 166_666_667, BAUD_RATE = 115200) (
    input  logic clk, rst,
    input  logic [7:0] tx_data,
    input  logic tx_valid,
    output logic tx,
    output logic tx_ready
);
    localparam CLKS_PER_BIT = CLK_FREQ / BAUD_RATE;

    enum logic [1:0] {IDLE, START, DATA, STOP} state;
    logic [15:0] clk_cnt;
    logic [2:0]  bit_cnt;
    logic [7:0]  data_reg;

    assign tx_ready = (state == IDLE);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE; tx <= 1; clk_cnt <= 0; bit_cnt <= 0; data_reg <= 0;
        end else begin
            case (state)
                IDLE: begin
                    tx <= 1; clk_cnt <= 0; bit_cnt <= 0;
                    if (tx_valid) begin
                        data_reg <= tx_data;
                        state <= START;
                    end
                end
                START: begin
                    tx <= 0;
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= 0; state <= DATA;
                    end else clk_cnt <= clk_cnt + 1;
                end
                DATA: begin
                    tx <= data_reg[bit_cnt];
                    if (clk_cnt == CLKS_PER_BIT-1) begin
                        clk_cnt <= 0;
                        if (bit_cnt == 7) state <= STOP;
                        else bit_cnt <= bit_cnt + 1;
                    end else clk_cnt <= clk_cnt + 1;
                end
                STOP: begin
                    tx <= 1;
                    if (clk_cnt == CLKS_PER_BIT-1) state <= IDLE;
                    else clk_cnt <= clk_cnt + 1;
                end
            endcase
        end
    end
endmodule
`timescale 1ns / 1ps

module vc_input_buffer #(
    parameter DATA_W = 8,
    parameter CORD_W = 2,
    parameter NUM_VCS = 2,
    parameter DEPTH = 16
)(
    input  logic clk,
    input  logic rst_n,

    input  logic              s_valid,
    input  logic              s_tlast,
    input  logic [3:0]        s_tdest,
    input  logic [DATA_W-1:0] s_tdata,
    input  logic [NUM_VCS-1:0]s_tid,
    output logic [NUM_VCS-1:0]s_ready,

    output logic              m_valid [NUM_VCS],
    output logic              m_tlast [NUM_VCS],
    output logic [3:0]        m_tdest [NUM_VCS],
    output logic [DATA_W-1:0] m_tdata [NUM_VCS],
    input  logic              m_ready [NUM_VCS]
);

    generate
        for (genvar v = 0; v < NUM_VCS; v++) begin : gen_vc_fifo

            logic fifo_we;
            assign fifo_we = s_valid && s_tid[v];

            localparam PACK_W = 1 + 4 + DATA_W;
            logic [PACK_W-1:0] wdata, rdata;

            assign wdata = {s_tlast, s_tdest, s_tdata};

            logic fifo_full, fifo_empty;

            assign s_ready[v] = ~fifo_full;

            sync_fifo #(
                .DATA_WIDTH(PACK_W),
                .DEPTH(DEPTH)
            ) vc_fifo_inst (
                .clk(clk),
                .rst_n(rst_n),
                .w_en(fifo_we && !fifo_full),
                .w_data(wdata),
                .r_en(m_ready[v] && !fifo_empty),
                .r_data(rdata),
                .full(fifo_full),
                .empty(fifo_empty)
            );

            assign m_valid[v] = ~fifo_empty;
            assign m_tlast[v] = rdata[PACK_W-1];
            assign m_tdest[v] = rdata[DATA_W+3 : DATA_W];
            assign m_tdata[v] = rdata[DATA_W-1 : 0];

        end
    endgenerate

endmodule

`timescale 1ns / 1ps

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

    logic [7:0] starve_cnt;
    logic       vc0_override;
    logic       vc1_is_active;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            starve_cnt   <= '0;
            vc0_override <= 1'b0;
        end else begin

            if (vc0_override) begin
                if (|raw_grant_vc0 && ready_out_vc0 && |(tlast_vc0 & raw_grant_vc0)) begin
                    vc0_override <= 1'b0;
                    starve_cnt   <= '0;
`ifdef SIM_DEBUG

                    $display("[%0t ns] [ARB DEBUG] %m finished VC0 Packet. Releasing Override.", $time);
`endif
                end
            end

            else begin
                if (|valid_vc0 && vc1_is_active) begin

                    if (starve_cnt < STARVE_LIMIT) starve_cnt <= starve_cnt + 1'b1;
                end else if (!(|valid_vc0)) begin
                    starve_cnt <= '0;
                end

                if (starve_cnt >= STARVE_LIMIT) begin
                    vc0_override <= 1'b1;
`ifdef SIM_DEBUG

                    $display("[%0t ns] [ARB DEBUG] %m Triggered VC0 Override! starve_cnt = %0d", $time, starve_cnt);
`endif
                end
            end
        end
    end

    assign vc1_is_active = |raw_grant_vc1 && !vc0_override;

    assign grant_vc1 = vc1_is_active ? raw_grant_vc1 : '0;
    assign grant_vc0 = !vc1_is_active ? raw_grant_vc0 : '0;

    assign ready_vc1 = vc1_is_active ? ready_out_vc1 : 1'b0;
    assign ready_vc0 = !vc1_is_active ? ready_out_vc0 : 1'b0;

    `ifdef FORMAL
        reg f_past_valid = 1'b0;
        always @(posedge clk) f_past_valid <= 1'b1;

        always @(*) begin
            if (rst_n && f_past_valid) begin
                if (raw_grant_vc1 != '0) assume($onehot(raw_grant_vc1));
                if (raw_grant_vc0 != '0) assume($onehot(raw_grant_vc0));

                assert_inv_starve_cap: assert(starve_cnt <= STARVE_LIMIT);

                if (!vc0_override) begin
                    assert_inv_wait_cap: assert(f_wait_cnt <= STARVE_LIMIT + 1);
                    if (starve_cnt < STARVE_LIMIT) begin
                        assert_inv_sync: assert(f_wait_cnt == starve_cnt);
                    end
                end
            end
        end

        always @(posedge clk) begin
            if (f_past_valid && $past(rst_n) && rst_n) begin

                if (!$past(vc0_override) && vc0_override) begin
                    assert_override_only_at_limit: assert($past(starve_cnt) >= STARVE_LIMIT);
                end

                if (vc0_override) begin
                    assert_no_vc1_during_override: assert(!vc1_is_active);
                end

                assert_vc_mutex: assert(!(|grant_vc1 && |grant_vc0));

                if (f_wait_cnt > (STARVE_LIMIT + 2)) begin
                    assert_bounded_starvation: assert(vc0_override || $past(vc0_override));
                end

                cover_vc1_preempts: cover($past(|grant_vc0) && !(|grant_vc0) && |grant_vc1);

                cover_override_activated: cover(!$past(vc0_override) && vc0_override);

                cover_override_completed: cover($past(vc0_override) && !vc0_override);
            end
        end

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

