set_clock_groups -name async_noc_clks -asynchronous \
    -group [get_clocks -include_generated_clocks *clk_out1_clk_wiz_0*] \
    -group [get_clocks -include_generated_clocks *clk_out2_clk_wiz_0*] \
    -group [get_clocks -include_generated_clocks *clk_out3_clk_wiz_0*] \
    -group [get_clocks -include_generated_clocks *clk_out4_clk_wiz_0*] \
    -group [get_clocks -include_generated_clocks *clk_out5_clk_wiz_0*]

# --- gray-code pointer buses ---
# set_max_delay -datapath_only \
#     -from [get_cells -hier -filter {NAME =~ *core_fifo/w_cnt/ptr_g_reg[*]}] \
#     -to   [get_cells -hier -filter {NAME =~ *core_fifo/sync_w2r/q1_reg[*]}] 10.000
# set_bus_skew \
#     -from [get_cells -hier -filter {NAME =~ *core_fifo/w_cnt/ptr_g_reg[*]}] \
#     -to   [get_cells -hier -filter {NAME =~ *core_fifo/sync_w2r/q1_reg[*]}] 10.000

# set_max_delay -datapath_only \
#     -from [get_cells -hier -filter {NAME =~ *core_fifo/r_cnt/ptr_g_reg[*]}] \
#     -to   [get_cells -hier -filter {NAME =~ *core_fifo/sync_r2w/q1_reg[*]}] 10.000
# set_bus_skew \
#     -from [get_cells -hier -filter {NAME =~ *core_fifo/r_cnt/ptr_g_reg[*]}] \
#     -to   [get_cells -hier -filter {NAME =~ *core_fifo/sync_r2w/q1_reg[*]}] 10.000

# # --- FIFO RAM data path (ที่ report_cdc ขึ้นเป็น CDC-15 384 รายการ) ---
# set_max_delay -datapath_only \
#     -from [get_cells -hier -filter {NAME =~ *core_ram/mem_reg*}] \
#     -to   [get_cells -hier -filter {NAME =~ *core_ram/rdata_reg[*]}] 10.000