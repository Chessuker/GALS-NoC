# 100 MHz Clock (Pin E3)
set_property -dict {PACKAGE_PIN E3 IOSTANDARD LVCMOS33} [get_ports clk_100mhz]
# create_clock -add -name sys_clk_pin -period 10.00 -waveform {0 5} [get_ports { clk_100mhz }];

# Reset Button (Pin C2 - Active Low)
set_property -dict {PACKAGE_PIN C2 IOSTANDARD LVCMOS33} [get_ports rst_n_btn]

# LEDs 4 ดวง (Pins H5, J5, T9, T8)
set_property -dict {PACKAGE_PIN H5 IOSTANDARD LVCMOS33} [get_ports {led[0]}]
set_property -dict {PACKAGE_PIN J5 IOSTANDARD LVCMOS33} [get_ports {led[1]}]
set_property -dict {PACKAGE_PIN T9 IOSTANDARD LVCMOS33} [get_ports {led[2]}]
set_property -dict {PACKAGE_PIN T10 IOSTANDARD LVCMOS33} [get_ports {led[3]}]

# ==============================================================================
# แจ้ง Vivado ว่า Clock ทั้ง 5 โดเมน แยกอิสระจากกัน (Asynchronous)
# (ป้องกันไม่ให้โปรแกรมไปพยายามปิด Timing ข้ามโดเมนที่ Async FIFO)
# ==============================================================================
# set_clock_groups -name async_noc_clks -asynchronous -group [get_clocks -include_generated_clocks *clk_out1_clk_wiz_0*] -group [get_clocks -include_generated_clocks *clk_out2_clk_wiz_0*] -group [get_clocks -include_generated_clocks *clk_out3_clk_wiz_0*] -group [get_clocks -include_generated_clocks *clk_out4_clk_wiz_0*] -group [get_clocks -include_generated_clocks *clk_out5_clk_wiz_0*]

# USB-UART (Pins A9, D10)
set_property -dict {PACKAGE_PIN D10 IOSTANDARD LVCMOS33} [get_ports uart_txd]
set_property -dict {PACKAGE_PIN A9 IOSTANDARD LVCMOS33} [get_ports uart_rxd]





create_debug_core u_ila_0 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_0]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_0]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_0]
set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_0]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_0]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_0]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_0]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_0]
set_property port_width 1 [get_debug_ports u_ila_0/clk]
connect_debug_port u_ila_0/clk [get_nets [list clk_gen/inst/clk_out2]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe0]
set_property port_width 32 [get_debug_ports u_ila_0/probe0]
connect_debug_port u_ila_0/probe0 [get_nets [list {uut_noc_top/mon_stall_cnt[0]} {uut_noc_top/mon_stall_cnt[1]} {uut_noc_top/mon_stall_cnt[2]} {uut_noc_top/mon_stall_cnt[3]} {uut_noc_top/mon_stall_cnt[4]} {uut_noc_top/mon_stall_cnt[5]} {uut_noc_top/mon_stall_cnt[6]} {uut_noc_top/mon_stall_cnt[7]} {uut_noc_top/mon_stall_cnt[8]} {uut_noc_top/mon_stall_cnt[9]} {uut_noc_top/mon_stall_cnt[10]} {uut_noc_top/mon_stall_cnt[11]} {uut_noc_top/mon_stall_cnt[12]} {uut_noc_top/mon_stall_cnt[13]} {uut_noc_top/mon_stall_cnt[14]} {uut_noc_top/mon_stall_cnt[15]} {uut_noc_top/mon_stall_cnt[16]} {uut_noc_top/mon_stall_cnt[17]} {uut_noc_top/mon_stall_cnt[18]} {uut_noc_top/mon_stall_cnt[19]} {uut_noc_top/mon_stall_cnt[20]} {uut_noc_top/mon_stall_cnt[21]} {uut_noc_top/mon_stall_cnt[22]} {uut_noc_top/mon_stall_cnt[23]} {uut_noc_top/mon_stall_cnt[24]} {uut_noc_top/mon_stall_cnt[25]} {uut_noc_top/mon_stall_cnt[26]} {uut_noc_top/mon_stall_cnt[27]} {uut_noc_top/mon_stall_cnt[28]} {uut_noc_top/mon_stall_cnt[29]} {uut_noc_top/mon_stall_cnt[30]} {uut_noc_top/mon_stall_cnt[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe1]
set_property port_width 32 [get_debug_ports u_ila_0/probe1]
connect_debug_port u_ila_0/probe1 [get_nets [list {uut_noc_top/mon_rx_stall_cnt[0]} {uut_noc_top/mon_rx_stall_cnt[1]} {uut_noc_top/mon_rx_stall_cnt[2]} {uut_noc_top/mon_rx_stall_cnt[3]} {uut_noc_top/mon_rx_stall_cnt[4]} {uut_noc_top/mon_rx_stall_cnt[5]} {uut_noc_top/mon_rx_stall_cnt[6]} {uut_noc_top/mon_rx_stall_cnt[7]} {uut_noc_top/mon_rx_stall_cnt[8]} {uut_noc_top/mon_rx_stall_cnt[9]} {uut_noc_top/mon_rx_stall_cnt[10]} {uut_noc_top/mon_rx_stall_cnt[11]} {uut_noc_top/mon_rx_stall_cnt[12]} {uut_noc_top/mon_rx_stall_cnt[13]} {uut_noc_top/mon_rx_stall_cnt[14]} {uut_noc_top/mon_rx_stall_cnt[15]} {uut_noc_top/mon_rx_stall_cnt[16]} {uut_noc_top/mon_rx_stall_cnt[17]} {uut_noc_top/mon_rx_stall_cnt[18]} {uut_noc_top/mon_rx_stall_cnt[19]} {uut_noc_top/mon_rx_stall_cnt[20]} {uut_noc_top/mon_rx_stall_cnt[21]} {uut_noc_top/mon_rx_stall_cnt[22]} {uut_noc_top/mon_rx_stall_cnt[23]} {uut_noc_top/mon_rx_stall_cnt[24]} {uut_noc_top/mon_rx_stall_cnt[25]} {uut_noc_top/mon_rx_stall_cnt[26]} {uut_noc_top/mon_rx_stall_cnt[27]} {uut_noc_top/mon_rx_stall_cnt[28]} {uut_noc_top/mon_rx_stall_cnt[29]} {uut_noc_top/mon_rx_stall_cnt[30]} {uut_noc_top/mon_rx_stall_cnt[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe2]
set_property port_width 32 [get_debug_ports u_ila_0/probe2]
connect_debug_port u_ila_0/probe2 [get_nets [list {uut_noc_top/mon_rx_pkt_cnt[0]} {uut_noc_top/mon_rx_pkt_cnt[1]} {uut_noc_top/mon_rx_pkt_cnt[2]} {uut_noc_top/mon_rx_pkt_cnt[3]} {uut_noc_top/mon_rx_pkt_cnt[4]} {uut_noc_top/mon_rx_pkt_cnt[5]} {uut_noc_top/mon_rx_pkt_cnt[6]} {uut_noc_top/mon_rx_pkt_cnt[7]} {uut_noc_top/mon_rx_pkt_cnt[8]} {uut_noc_top/mon_rx_pkt_cnt[9]} {uut_noc_top/mon_rx_pkt_cnt[10]} {uut_noc_top/mon_rx_pkt_cnt[11]} {uut_noc_top/mon_rx_pkt_cnt[12]} {uut_noc_top/mon_rx_pkt_cnt[13]} {uut_noc_top/mon_rx_pkt_cnt[14]} {uut_noc_top/mon_rx_pkt_cnt[15]} {uut_noc_top/mon_rx_pkt_cnt[16]} {uut_noc_top/mon_rx_pkt_cnt[17]} {uut_noc_top/mon_rx_pkt_cnt[18]} {uut_noc_top/mon_rx_pkt_cnt[19]} {uut_noc_top/mon_rx_pkt_cnt[20]} {uut_noc_top/mon_rx_pkt_cnt[21]} {uut_noc_top/mon_rx_pkt_cnt[22]} {uut_noc_top/mon_rx_pkt_cnt[23]} {uut_noc_top/mon_rx_pkt_cnt[24]} {uut_noc_top/mon_rx_pkt_cnt[25]} {uut_noc_top/mon_rx_pkt_cnt[26]} {uut_noc_top/mon_rx_pkt_cnt[27]} {uut_noc_top/mon_rx_pkt_cnt[28]} {uut_noc_top/mon_rx_pkt_cnt[29]} {uut_noc_top/mon_rx_pkt_cnt[30]} {uut_noc_top/mon_rx_pkt_cnt[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe3]
set_property port_width 32 [get_debug_ports u_ila_0/probe3]
connect_debug_port u_ila_0/probe3 [get_nets [list {uut_noc_top/mon_active_cnt[0]} {uut_noc_top/mon_active_cnt[1]} {uut_noc_top/mon_active_cnt[2]} {uut_noc_top/mon_active_cnt[3]} {uut_noc_top/mon_active_cnt[4]} {uut_noc_top/mon_active_cnt[5]} {uut_noc_top/mon_active_cnt[6]} {uut_noc_top/mon_active_cnt[7]} {uut_noc_top/mon_active_cnt[8]} {uut_noc_top/mon_active_cnt[9]} {uut_noc_top/mon_active_cnt[10]} {uut_noc_top/mon_active_cnt[11]} {uut_noc_top/mon_active_cnt[12]} {uut_noc_top/mon_active_cnt[13]} {uut_noc_top/mon_active_cnt[14]} {uut_noc_top/mon_active_cnt[15]} {uut_noc_top/mon_active_cnt[16]} {uut_noc_top/mon_active_cnt[17]} {uut_noc_top/mon_active_cnt[18]} {uut_noc_top/mon_active_cnt[19]} {uut_noc_top/mon_active_cnt[20]} {uut_noc_top/mon_active_cnt[21]} {uut_noc_top/mon_active_cnt[22]} {uut_noc_top/mon_active_cnt[23]} {uut_noc_top/mon_active_cnt[24]} {uut_noc_top/mon_active_cnt[25]} {uut_noc_top/mon_active_cnt[26]} {uut_noc_top/mon_active_cnt[27]} {uut_noc_top/mon_active_cnt[28]} {uut_noc_top/mon_active_cnt[29]} {uut_noc_top/mon_active_cnt[30]} {uut_noc_top/mon_active_cnt[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe4]
set_property port_width 32 [get_debug_ports u_ila_0/probe4]
connect_debug_port u_ila_0/probe4 [get_nets [list {uut_noc_top/mon_flit_cnt[0]} {uut_noc_top/mon_flit_cnt[1]} {uut_noc_top/mon_flit_cnt[2]} {uut_noc_top/mon_flit_cnt[3]} {uut_noc_top/mon_flit_cnt[4]} {uut_noc_top/mon_flit_cnt[5]} {uut_noc_top/mon_flit_cnt[6]} {uut_noc_top/mon_flit_cnt[7]} {uut_noc_top/mon_flit_cnt[8]} {uut_noc_top/mon_flit_cnt[9]} {uut_noc_top/mon_flit_cnt[10]} {uut_noc_top/mon_flit_cnt[11]} {uut_noc_top/mon_flit_cnt[12]} {uut_noc_top/mon_flit_cnt[13]} {uut_noc_top/mon_flit_cnt[14]} {uut_noc_top/mon_flit_cnt[15]} {uut_noc_top/mon_flit_cnt[16]} {uut_noc_top/mon_flit_cnt[17]} {uut_noc_top/mon_flit_cnt[18]} {uut_noc_top/mon_flit_cnt[19]} {uut_noc_top/mon_flit_cnt[20]} {uut_noc_top/mon_flit_cnt[21]} {uut_noc_top/mon_flit_cnt[22]} {uut_noc_top/mon_flit_cnt[23]} {uut_noc_top/mon_flit_cnt[24]} {uut_noc_top/mon_flit_cnt[25]} {uut_noc_top/mon_flit_cnt[26]} {uut_noc_top/mon_flit_cnt[27]} {uut_noc_top/mon_flit_cnt[28]} {uut_noc_top/mon_flit_cnt[29]} {uut_noc_top/mon_flit_cnt[30]} {uut_noc_top/mon_flit_cnt[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe5]
set_property port_width 32 [get_debug_ports u_ila_0/probe5]
connect_debug_port u_ila_0/probe5 [get_nets [list {uut_noc_top/mon_rx_active_cnt[0]} {uut_noc_top/mon_rx_active_cnt[1]} {uut_noc_top/mon_rx_active_cnt[2]} {uut_noc_top/mon_rx_active_cnt[3]} {uut_noc_top/mon_rx_active_cnt[4]} {uut_noc_top/mon_rx_active_cnt[5]} {uut_noc_top/mon_rx_active_cnt[6]} {uut_noc_top/mon_rx_active_cnt[7]} {uut_noc_top/mon_rx_active_cnt[8]} {uut_noc_top/mon_rx_active_cnt[9]} {uut_noc_top/mon_rx_active_cnt[10]} {uut_noc_top/mon_rx_active_cnt[11]} {uut_noc_top/mon_rx_active_cnt[12]} {uut_noc_top/mon_rx_active_cnt[13]} {uut_noc_top/mon_rx_active_cnt[14]} {uut_noc_top/mon_rx_active_cnt[15]} {uut_noc_top/mon_rx_active_cnt[16]} {uut_noc_top/mon_rx_active_cnt[17]} {uut_noc_top/mon_rx_active_cnt[18]} {uut_noc_top/mon_rx_active_cnt[19]} {uut_noc_top/mon_rx_active_cnt[20]} {uut_noc_top/mon_rx_active_cnt[21]} {uut_noc_top/mon_rx_active_cnt[22]} {uut_noc_top/mon_rx_active_cnt[23]} {uut_noc_top/mon_rx_active_cnt[24]} {uut_noc_top/mon_rx_active_cnt[25]} {uut_noc_top/mon_rx_active_cnt[26]} {uut_noc_top/mon_rx_active_cnt[27]} {uut_noc_top/mon_rx_active_cnt[28]} {uut_noc_top/mon_rx_active_cnt[29]} {uut_noc_top/mon_rx_active_cnt[30]} {uut_noc_top/mon_rx_active_cnt[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe6]
set_property port_width 32 [get_debug_ports u_ila_0/probe6]
connect_debug_port u_ila_0/probe6 [get_nets [list {uut_noc_top/mon_pkt_cnt[0]} {uut_noc_top/mon_pkt_cnt[1]} {uut_noc_top/mon_pkt_cnt[2]} {uut_noc_top/mon_pkt_cnt[3]} {uut_noc_top/mon_pkt_cnt[4]} {uut_noc_top/mon_pkt_cnt[5]} {uut_noc_top/mon_pkt_cnt[6]} {uut_noc_top/mon_pkt_cnt[7]} {uut_noc_top/mon_pkt_cnt[8]} {uut_noc_top/mon_pkt_cnt[9]} {uut_noc_top/mon_pkt_cnt[10]} {uut_noc_top/mon_pkt_cnt[11]} {uut_noc_top/mon_pkt_cnt[12]} {uut_noc_top/mon_pkt_cnt[13]} {uut_noc_top/mon_pkt_cnt[14]} {uut_noc_top/mon_pkt_cnt[15]} {uut_noc_top/mon_pkt_cnt[16]} {uut_noc_top/mon_pkt_cnt[17]} {uut_noc_top/mon_pkt_cnt[18]} {uut_noc_top/mon_pkt_cnt[19]} {uut_noc_top/mon_pkt_cnt[20]} {uut_noc_top/mon_pkt_cnt[21]} {uut_noc_top/mon_pkt_cnt[22]} {uut_noc_top/mon_pkt_cnt[23]} {uut_noc_top/mon_pkt_cnt[24]} {uut_noc_top/mon_pkt_cnt[25]} {uut_noc_top/mon_pkt_cnt[26]} {uut_noc_top/mon_pkt_cnt[27]} {uut_noc_top/mon_pkt_cnt[28]} {uut_noc_top/mon_pkt_cnt[29]} {uut_noc_top/mon_pkt_cnt[30]} {uut_noc_top/mon_pkt_cnt[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe7]
set_property port_width 32 [get_debug_ports u_ila_0/probe7]
connect_debug_port u_ila_0/probe7 [get_nets [list {uut_noc_top/mon_rx_flit_cnt[0]} {uut_noc_top/mon_rx_flit_cnt[1]} {uut_noc_top/mon_rx_flit_cnt[2]} {uut_noc_top/mon_rx_flit_cnt[3]} {uut_noc_top/mon_rx_flit_cnt[4]} {uut_noc_top/mon_rx_flit_cnt[5]} {uut_noc_top/mon_rx_flit_cnt[6]} {uut_noc_top/mon_rx_flit_cnt[7]} {uut_noc_top/mon_rx_flit_cnt[8]} {uut_noc_top/mon_rx_flit_cnt[9]} {uut_noc_top/mon_rx_flit_cnt[10]} {uut_noc_top/mon_rx_flit_cnt[11]} {uut_noc_top/mon_rx_flit_cnt[12]} {uut_noc_top/mon_rx_flit_cnt[13]} {uut_noc_top/mon_rx_flit_cnt[14]} {uut_noc_top/mon_rx_flit_cnt[15]} {uut_noc_top/mon_rx_flit_cnt[16]} {uut_noc_top/mon_rx_flit_cnt[17]} {uut_noc_top/mon_rx_flit_cnt[18]} {uut_noc_top/mon_rx_flit_cnt[19]} {uut_noc_top/mon_rx_flit_cnt[20]} {uut_noc_top/mon_rx_flit_cnt[21]} {uut_noc_top/mon_rx_flit_cnt[22]} {uut_noc_top/mon_rx_flit_cnt[23]} {uut_noc_top/mon_rx_flit_cnt[24]} {uut_noc_top/mon_rx_flit_cnt[25]} {uut_noc_top/mon_rx_flit_cnt[26]} {uut_noc_top/mon_rx_flit_cnt[27]} {uut_noc_top/mon_rx_flit_cnt[28]} {uut_noc_top/mon_rx_flit_cnt[29]} {uut_noc_top/mon_rx_flit_cnt[30]} {uut_noc_top/mon_rx_flit_cnt[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe8]
set_property port_width 32 [get_debug_ports u_ila_0/probe8]
connect_debug_port u_ila_0/probe8 [get_nets [list {u_stress/agent_00/tx_stall_cnt[0]} {u_stress/agent_00/tx_stall_cnt[1]} {u_stress/agent_00/tx_stall_cnt[2]} {u_stress/agent_00/tx_stall_cnt[3]} {u_stress/agent_00/tx_stall_cnt[4]} {u_stress/agent_00/tx_stall_cnt[5]} {u_stress/agent_00/tx_stall_cnt[6]} {u_stress/agent_00/tx_stall_cnt[7]} {u_stress/agent_00/tx_stall_cnt[8]} {u_stress/agent_00/tx_stall_cnt[9]} {u_stress/agent_00/tx_stall_cnt[10]} {u_stress/agent_00/tx_stall_cnt[11]} {u_stress/agent_00/tx_stall_cnt[12]} {u_stress/agent_00/tx_stall_cnt[13]} {u_stress/agent_00/tx_stall_cnt[14]} {u_stress/agent_00/tx_stall_cnt[15]} {u_stress/agent_00/tx_stall_cnt[16]} {u_stress/agent_00/tx_stall_cnt[17]} {u_stress/agent_00/tx_stall_cnt[18]} {u_stress/agent_00/tx_stall_cnt[19]} {u_stress/agent_00/tx_stall_cnt[20]} {u_stress/agent_00/tx_stall_cnt[21]} {u_stress/agent_00/tx_stall_cnt[22]} {u_stress/agent_00/tx_stall_cnt[23]} {u_stress/agent_00/tx_stall_cnt[24]} {u_stress/agent_00/tx_stall_cnt[25]} {u_stress/agent_00/tx_stall_cnt[26]} {u_stress/agent_00/tx_stall_cnt[27]} {u_stress/agent_00/tx_stall_cnt[28]} {u_stress/agent_00/tx_stall_cnt[29]} {u_stress/agent_00/tx_stall_cnt[30]} {u_stress/agent_00/tx_stall_cnt[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe9]
set_property port_width 32 [get_debug_ports u_ila_0/probe9]
connect_debug_port u_ila_0/probe9 [get_nets [list {u_stress/agent_00/rx_err_cnt[0]} {u_stress/agent_00/rx_err_cnt[1]} {u_stress/agent_00/rx_err_cnt[2]} {u_stress/agent_00/rx_err_cnt[3]} {u_stress/agent_00/rx_err_cnt[4]} {u_stress/agent_00/rx_err_cnt[5]} {u_stress/agent_00/rx_err_cnt[6]} {u_stress/agent_00/rx_err_cnt[7]} {u_stress/agent_00/rx_err_cnt[8]} {u_stress/agent_00/rx_err_cnt[9]} {u_stress/agent_00/rx_err_cnt[10]} {u_stress/agent_00/rx_err_cnt[11]} {u_stress/agent_00/rx_err_cnt[12]} {u_stress/agent_00/rx_err_cnt[13]} {u_stress/agent_00/rx_err_cnt[14]} {u_stress/agent_00/rx_err_cnt[15]} {u_stress/agent_00/rx_err_cnt[16]} {u_stress/agent_00/rx_err_cnt[17]} {u_stress/agent_00/rx_err_cnt[18]} {u_stress/agent_00/rx_err_cnt[19]} {u_stress/agent_00/rx_err_cnt[20]} {u_stress/agent_00/rx_err_cnt[21]} {u_stress/agent_00/rx_err_cnt[22]} {u_stress/agent_00/rx_err_cnt[23]} {u_stress/agent_00/rx_err_cnt[24]} {u_stress/agent_00/rx_err_cnt[25]} {u_stress/agent_00/rx_err_cnt[26]} {u_stress/agent_00/rx_err_cnt[27]} {u_stress/agent_00/rx_err_cnt[28]} {u_stress/agent_00/rx_err_cnt[29]} {u_stress/agent_00/rx_err_cnt[30]} {u_stress/agent_00/rx_err_cnt[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe10]
set_property port_width 32 [get_debug_ports u_ila_0/probe10]
connect_debug_port u_ila_0/probe10 [get_nets [list {u_stress/agent_00/rx_vc1_cnt[0]} {u_stress/agent_00/rx_vc1_cnt[1]} {u_stress/agent_00/rx_vc1_cnt[2]} {u_stress/agent_00/rx_vc1_cnt[3]} {u_stress/agent_00/rx_vc1_cnt[4]} {u_stress/agent_00/rx_vc1_cnt[5]} {u_stress/agent_00/rx_vc1_cnt[6]} {u_stress/agent_00/rx_vc1_cnt[7]} {u_stress/agent_00/rx_vc1_cnt[8]} {u_stress/agent_00/rx_vc1_cnt[9]} {u_stress/agent_00/rx_vc1_cnt[10]} {u_stress/agent_00/rx_vc1_cnt[11]} {u_stress/agent_00/rx_vc1_cnt[12]} {u_stress/agent_00/rx_vc1_cnt[13]} {u_stress/agent_00/rx_vc1_cnt[14]} {u_stress/agent_00/rx_vc1_cnt[15]} {u_stress/agent_00/rx_vc1_cnt[16]} {u_stress/agent_00/rx_vc1_cnt[17]} {u_stress/agent_00/rx_vc1_cnt[18]} {u_stress/agent_00/rx_vc1_cnt[19]} {u_stress/agent_00/rx_vc1_cnt[20]} {u_stress/agent_00/rx_vc1_cnt[21]} {u_stress/agent_00/rx_vc1_cnt[22]} {u_stress/agent_00/rx_vc1_cnt[23]} {u_stress/agent_00/rx_vc1_cnt[24]} {u_stress/agent_00/rx_vc1_cnt[25]} {u_stress/agent_00/rx_vc1_cnt[26]} {u_stress/agent_00/rx_vc1_cnt[27]} {u_stress/agent_00/rx_vc1_cnt[28]} {u_stress/agent_00/rx_vc1_cnt[29]} {u_stress/agent_00/rx_vc1_cnt[30]} {u_stress/agent_00/rx_vc1_cnt[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe11]
set_property port_width 32 [get_debug_ports u_ila_0/probe11]
connect_debug_port u_ila_0/probe11 [get_nets [list {u_stress/agent_00/rx_vc0_cnt[0]} {u_stress/agent_00/rx_vc0_cnt[1]} {u_stress/agent_00/rx_vc0_cnt[2]} {u_stress/agent_00/rx_vc0_cnt[3]} {u_stress/agent_00/rx_vc0_cnt[4]} {u_stress/agent_00/rx_vc0_cnt[5]} {u_stress/agent_00/rx_vc0_cnt[6]} {u_stress/agent_00/rx_vc0_cnt[7]} {u_stress/agent_00/rx_vc0_cnt[8]} {u_stress/agent_00/rx_vc0_cnt[9]} {u_stress/agent_00/rx_vc0_cnt[10]} {u_stress/agent_00/rx_vc0_cnt[11]} {u_stress/agent_00/rx_vc0_cnt[12]} {u_stress/agent_00/rx_vc0_cnt[13]} {u_stress/agent_00/rx_vc0_cnt[14]} {u_stress/agent_00/rx_vc0_cnt[15]} {u_stress/agent_00/rx_vc0_cnt[16]} {u_stress/agent_00/rx_vc0_cnt[17]} {u_stress/agent_00/rx_vc0_cnt[18]} {u_stress/agent_00/rx_vc0_cnt[19]} {u_stress/agent_00/rx_vc0_cnt[20]} {u_stress/agent_00/rx_vc0_cnt[21]} {u_stress/agent_00/rx_vc0_cnt[22]} {u_stress/agent_00/rx_vc0_cnt[23]} {u_stress/agent_00/rx_vc0_cnt[24]} {u_stress/agent_00/rx_vc0_cnt[25]} {u_stress/agent_00/rx_vc0_cnt[26]} {u_stress/agent_00/rx_vc0_cnt[27]} {u_stress/agent_00/rx_vc0_cnt[28]} {u_stress/agent_00/rx_vc0_cnt[29]} {u_stress/agent_00/rx_vc0_cnt[30]} {u_stress/agent_00/rx_vc0_cnt[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe12]
set_property port_width 32 [get_debug_ports u_ila_0/probe12]
connect_debug_port u_ila_0/probe12 [get_nets [list {u_stress/agent_00/tx_flit_cnt[0]} {u_stress/agent_00/tx_flit_cnt[1]} {u_stress/agent_00/tx_flit_cnt[2]} {u_stress/agent_00/tx_flit_cnt[3]} {u_stress/agent_00/tx_flit_cnt[4]} {u_stress/agent_00/tx_flit_cnt[5]} {u_stress/agent_00/tx_flit_cnt[6]} {u_stress/agent_00/tx_flit_cnt[7]} {u_stress/agent_00/tx_flit_cnt[8]} {u_stress/agent_00/tx_flit_cnt[9]} {u_stress/agent_00/tx_flit_cnt[10]} {u_stress/agent_00/tx_flit_cnt[11]} {u_stress/agent_00/tx_flit_cnt[12]} {u_stress/agent_00/tx_flit_cnt[13]} {u_stress/agent_00/tx_flit_cnt[14]} {u_stress/agent_00/tx_flit_cnt[15]} {u_stress/agent_00/tx_flit_cnt[16]} {u_stress/agent_00/tx_flit_cnt[17]} {u_stress/agent_00/tx_flit_cnt[18]} {u_stress/agent_00/tx_flit_cnt[19]} {u_stress/agent_00/tx_flit_cnt[20]} {u_stress/agent_00/tx_flit_cnt[21]} {u_stress/agent_00/tx_flit_cnt[22]} {u_stress/agent_00/tx_flit_cnt[23]} {u_stress/agent_00/tx_flit_cnt[24]} {u_stress/agent_00/tx_flit_cnt[25]} {u_stress/agent_00/tx_flit_cnt[26]} {u_stress/agent_00/tx_flit_cnt[27]} {u_stress/agent_00/tx_flit_cnt[28]} {u_stress/agent_00/tx_flit_cnt[29]} {u_stress/agent_00/tx_flit_cnt[30]} {u_stress/agent_00/tx_flit_cnt[31]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe13]
set_property port_width 2 [get_debug_ports u_ila_0/probe13]
connect_debug_port u_ila_0/probe13 [get_nets [list {u_stress/agent_00/state_dbg[0]} {u_stress/agent_00/state_dbg[1]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe14]
set_property port_width 4 [get_debug_ports u_ila_0/probe14]
connect_debug_port u_ila_0/probe14 [get_nets [list {u_stress/agent_00/rx_tdest_dbg[0]} {u_stress/agent_00/rx_tdest_dbg[1]} {u_stress/agent_00/rx_tdest_dbg[2]} {u_stress/agent_00/rx_tdest_dbg[3]}]]
create_debug_port u_ila_0 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_0/probe15]
set_property port_width 1 [get_debug_ports u_ila_0/probe15]
connect_debug_port u_ila_0/probe15 [get_nets [list u_stress/agent_00/test_done]]
create_debug_core u_ila_1 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_1]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_1]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_1]
set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_1]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_1]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_1]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_1]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_1]
set_property port_width 1 [get_debug_ports u_ila_1/clk]
connect_debug_port u_ila_1/clk [get_nets [list clk_gen/inst/clk_out3]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_1/probe0]
set_property port_width 2 [get_debug_ports u_ila_1/probe0]
connect_debug_port u_ila_1/probe0 [get_nets [list {u_stress/agent_01/state_dbg[0]} {u_stress/agent_01/state_dbg[1]}]]
create_debug_port u_ila_1 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_1/probe1]
set_property port_width 32 [get_debug_ports u_ila_1/probe1]
connect_debug_port u_ila_1/probe1 [get_nets [list {u_stress/agent_01/rx_err_cnt[0]} {u_stress/agent_01/rx_err_cnt[1]} {u_stress/agent_01/rx_err_cnt[2]} {u_stress/agent_01/rx_err_cnt[3]} {u_stress/agent_01/rx_err_cnt[4]} {u_stress/agent_01/rx_err_cnt[5]} {u_stress/agent_01/rx_err_cnt[6]} {u_stress/agent_01/rx_err_cnt[7]} {u_stress/agent_01/rx_err_cnt[8]} {u_stress/agent_01/rx_err_cnt[9]} {u_stress/agent_01/rx_err_cnt[10]} {u_stress/agent_01/rx_err_cnt[11]} {u_stress/agent_01/rx_err_cnt[12]} {u_stress/agent_01/rx_err_cnt[13]} {u_stress/agent_01/rx_err_cnt[14]} {u_stress/agent_01/rx_err_cnt[15]} {u_stress/agent_01/rx_err_cnt[16]} {u_stress/agent_01/rx_err_cnt[17]} {u_stress/agent_01/rx_err_cnt[18]} {u_stress/agent_01/rx_err_cnt[19]} {u_stress/agent_01/rx_err_cnt[20]} {u_stress/agent_01/rx_err_cnt[21]} {u_stress/agent_01/rx_err_cnt[22]} {u_stress/agent_01/rx_err_cnt[23]} {u_stress/agent_01/rx_err_cnt[24]} {u_stress/agent_01/rx_err_cnt[25]} {u_stress/agent_01/rx_err_cnt[26]} {u_stress/agent_01/rx_err_cnt[27]} {u_stress/agent_01/rx_err_cnt[28]} {u_stress/agent_01/rx_err_cnt[29]} {u_stress/agent_01/rx_err_cnt[30]} {u_stress/agent_01/rx_err_cnt[31]}]]
create_debug_port u_ila_1 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_1/probe2]
set_property port_width 32 [get_debug_ports u_ila_1/probe2]
connect_debug_port u_ila_1/probe2 [get_nets [list {u_stress/agent_01/rx_vc1_cnt[0]} {u_stress/agent_01/rx_vc1_cnt[1]} {u_stress/agent_01/rx_vc1_cnt[2]} {u_stress/agent_01/rx_vc1_cnt[3]} {u_stress/agent_01/rx_vc1_cnt[4]} {u_stress/agent_01/rx_vc1_cnt[5]} {u_stress/agent_01/rx_vc1_cnt[6]} {u_stress/agent_01/rx_vc1_cnt[7]} {u_stress/agent_01/rx_vc1_cnt[8]} {u_stress/agent_01/rx_vc1_cnt[9]} {u_stress/agent_01/rx_vc1_cnt[10]} {u_stress/agent_01/rx_vc1_cnt[11]} {u_stress/agent_01/rx_vc1_cnt[12]} {u_stress/agent_01/rx_vc1_cnt[13]} {u_stress/agent_01/rx_vc1_cnt[14]} {u_stress/agent_01/rx_vc1_cnt[15]} {u_stress/agent_01/rx_vc1_cnt[16]} {u_stress/agent_01/rx_vc1_cnt[17]} {u_stress/agent_01/rx_vc1_cnt[18]} {u_stress/agent_01/rx_vc1_cnt[19]} {u_stress/agent_01/rx_vc1_cnt[20]} {u_stress/agent_01/rx_vc1_cnt[21]} {u_stress/agent_01/rx_vc1_cnt[22]} {u_stress/agent_01/rx_vc1_cnt[23]} {u_stress/agent_01/rx_vc1_cnt[24]} {u_stress/agent_01/rx_vc1_cnt[25]} {u_stress/agent_01/rx_vc1_cnt[26]} {u_stress/agent_01/rx_vc1_cnt[27]} {u_stress/agent_01/rx_vc1_cnt[28]} {u_stress/agent_01/rx_vc1_cnt[29]} {u_stress/agent_01/rx_vc1_cnt[30]} {u_stress/agent_01/rx_vc1_cnt[31]}]]
create_debug_port u_ila_1 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_1/probe3]
set_property port_width 32 [get_debug_ports u_ila_1/probe3]
connect_debug_port u_ila_1/probe3 [get_nets [list {u_stress/agent_01/tx_flit_cnt[0]} {u_stress/agent_01/tx_flit_cnt[1]} {u_stress/agent_01/tx_flit_cnt[2]} {u_stress/agent_01/tx_flit_cnt[3]} {u_stress/agent_01/tx_flit_cnt[4]} {u_stress/agent_01/tx_flit_cnt[5]} {u_stress/agent_01/tx_flit_cnt[6]} {u_stress/agent_01/tx_flit_cnt[7]} {u_stress/agent_01/tx_flit_cnt[8]} {u_stress/agent_01/tx_flit_cnt[9]} {u_stress/agent_01/tx_flit_cnt[10]} {u_stress/agent_01/tx_flit_cnt[11]} {u_stress/agent_01/tx_flit_cnt[12]} {u_stress/agent_01/tx_flit_cnt[13]} {u_stress/agent_01/tx_flit_cnt[14]} {u_stress/agent_01/tx_flit_cnt[15]} {u_stress/agent_01/tx_flit_cnt[16]} {u_stress/agent_01/tx_flit_cnt[17]} {u_stress/agent_01/tx_flit_cnt[18]} {u_stress/agent_01/tx_flit_cnt[19]} {u_stress/agent_01/tx_flit_cnt[20]} {u_stress/agent_01/tx_flit_cnt[21]} {u_stress/agent_01/tx_flit_cnt[22]} {u_stress/agent_01/tx_flit_cnt[23]} {u_stress/agent_01/tx_flit_cnt[24]} {u_stress/agent_01/tx_flit_cnt[25]} {u_stress/agent_01/tx_flit_cnt[26]} {u_stress/agent_01/tx_flit_cnt[27]} {u_stress/agent_01/tx_flit_cnt[28]} {u_stress/agent_01/tx_flit_cnt[29]} {u_stress/agent_01/tx_flit_cnt[30]} {u_stress/agent_01/tx_flit_cnt[31]}]]
create_debug_port u_ila_1 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_1/probe4]
set_property port_width 4 [get_debug_ports u_ila_1/probe4]
connect_debug_port u_ila_1/probe4 [get_nets [list {u_stress/agent_01/rx_tdest_dbg[0]} {u_stress/agent_01/rx_tdest_dbg[1]} {u_stress/agent_01/rx_tdest_dbg[2]} {u_stress/agent_01/rx_tdest_dbg[3]}]]
create_debug_port u_ila_1 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_1/probe5]
set_property port_width 32 [get_debug_ports u_ila_1/probe5]
connect_debug_port u_ila_1/probe5 [get_nets [list {u_stress/agent_01/rx_vc0_cnt[0]} {u_stress/agent_01/rx_vc0_cnt[1]} {u_stress/agent_01/rx_vc0_cnt[2]} {u_stress/agent_01/rx_vc0_cnt[3]} {u_stress/agent_01/rx_vc0_cnt[4]} {u_stress/agent_01/rx_vc0_cnt[5]} {u_stress/agent_01/rx_vc0_cnt[6]} {u_stress/agent_01/rx_vc0_cnt[7]} {u_stress/agent_01/rx_vc0_cnt[8]} {u_stress/agent_01/rx_vc0_cnt[9]} {u_stress/agent_01/rx_vc0_cnt[10]} {u_stress/agent_01/rx_vc0_cnt[11]} {u_stress/agent_01/rx_vc0_cnt[12]} {u_stress/agent_01/rx_vc0_cnt[13]} {u_stress/agent_01/rx_vc0_cnt[14]} {u_stress/agent_01/rx_vc0_cnt[15]} {u_stress/agent_01/rx_vc0_cnt[16]} {u_stress/agent_01/rx_vc0_cnt[17]} {u_stress/agent_01/rx_vc0_cnt[18]} {u_stress/agent_01/rx_vc0_cnt[19]} {u_stress/agent_01/rx_vc0_cnt[20]} {u_stress/agent_01/rx_vc0_cnt[21]} {u_stress/agent_01/rx_vc0_cnt[22]} {u_stress/agent_01/rx_vc0_cnt[23]} {u_stress/agent_01/rx_vc0_cnt[24]} {u_stress/agent_01/rx_vc0_cnt[25]} {u_stress/agent_01/rx_vc0_cnt[26]} {u_stress/agent_01/rx_vc0_cnt[27]} {u_stress/agent_01/rx_vc0_cnt[28]} {u_stress/agent_01/rx_vc0_cnt[29]} {u_stress/agent_01/rx_vc0_cnt[30]} {u_stress/agent_01/rx_vc0_cnt[31]}]]
create_debug_port u_ila_1 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_1/probe6]
set_property port_width 32 [get_debug_ports u_ila_1/probe6]
connect_debug_port u_ila_1/probe6 [get_nets [list {u_stress/agent_01/tx_stall_cnt[0]} {u_stress/agent_01/tx_stall_cnt[1]} {u_stress/agent_01/tx_stall_cnt[2]} {u_stress/agent_01/tx_stall_cnt[3]} {u_stress/agent_01/tx_stall_cnt[4]} {u_stress/agent_01/tx_stall_cnt[5]} {u_stress/agent_01/tx_stall_cnt[6]} {u_stress/agent_01/tx_stall_cnt[7]} {u_stress/agent_01/tx_stall_cnt[8]} {u_stress/agent_01/tx_stall_cnt[9]} {u_stress/agent_01/tx_stall_cnt[10]} {u_stress/agent_01/tx_stall_cnt[11]} {u_stress/agent_01/tx_stall_cnt[12]} {u_stress/agent_01/tx_stall_cnt[13]} {u_stress/agent_01/tx_stall_cnt[14]} {u_stress/agent_01/tx_stall_cnt[15]} {u_stress/agent_01/tx_stall_cnt[16]} {u_stress/agent_01/tx_stall_cnt[17]} {u_stress/agent_01/tx_stall_cnt[18]} {u_stress/agent_01/tx_stall_cnt[19]} {u_stress/agent_01/tx_stall_cnt[20]} {u_stress/agent_01/tx_stall_cnt[21]} {u_stress/agent_01/tx_stall_cnt[22]} {u_stress/agent_01/tx_stall_cnt[23]} {u_stress/agent_01/tx_stall_cnt[24]} {u_stress/agent_01/tx_stall_cnt[25]} {u_stress/agent_01/tx_stall_cnt[26]} {u_stress/agent_01/tx_stall_cnt[27]} {u_stress/agent_01/tx_stall_cnt[28]} {u_stress/agent_01/tx_stall_cnt[29]} {u_stress/agent_01/tx_stall_cnt[30]} {u_stress/agent_01/tx_stall_cnt[31]}]]
create_debug_port u_ila_1 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_1/probe7]
set_property port_width 1 [get_debug_ports u_ila_1/probe7]
connect_debug_port u_ila_1/probe7 [get_nets [list u_stress/agent_01/test_done]]
create_debug_core u_ila_2 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_2]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_2]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_2]
set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_2]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_2]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_2]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_2]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_2]
set_property port_width 1 [get_debug_ports u_ila_2/clk]
connect_debug_port u_ila_2/clk [get_nets [list clk_gen/inst/clk_out4]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe0]
set_property port_width 2 [get_debug_ports u_ila_2/probe0]
connect_debug_port u_ila_2/probe0 [get_nets [list {u_stress/agent_10/state_dbg[0]} {u_stress/agent_10/state_dbg[1]}]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe1]
set_property port_width 32 [get_debug_ports u_ila_2/probe1]
connect_debug_port u_ila_2/probe1 [get_nets [list {u_stress/agent_10/rx_vc0_cnt[0]} {u_stress/agent_10/rx_vc0_cnt[1]} {u_stress/agent_10/rx_vc0_cnt[2]} {u_stress/agent_10/rx_vc0_cnt[3]} {u_stress/agent_10/rx_vc0_cnt[4]} {u_stress/agent_10/rx_vc0_cnt[5]} {u_stress/agent_10/rx_vc0_cnt[6]} {u_stress/agent_10/rx_vc0_cnt[7]} {u_stress/agent_10/rx_vc0_cnt[8]} {u_stress/agent_10/rx_vc0_cnt[9]} {u_stress/agent_10/rx_vc0_cnt[10]} {u_stress/agent_10/rx_vc0_cnt[11]} {u_stress/agent_10/rx_vc0_cnt[12]} {u_stress/agent_10/rx_vc0_cnt[13]} {u_stress/agent_10/rx_vc0_cnt[14]} {u_stress/agent_10/rx_vc0_cnt[15]} {u_stress/agent_10/rx_vc0_cnt[16]} {u_stress/agent_10/rx_vc0_cnt[17]} {u_stress/agent_10/rx_vc0_cnt[18]} {u_stress/agent_10/rx_vc0_cnt[19]} {u_stress/agent_10/rx_vc0_cnt[20]} {u_stress/agent_10/rx_vc0_cnt[21]} {u_stress/agent_10/rx_vc0_cnt[22]} {u_stress/agent_10/rx_vc0_cnt[23]} {u_stress/agent_10/rx_vc0_cnt[24]} {u_stress/agent_10/rx_vc0_cnt[25]} {u_stress/agent_10/rx_vc0_cnt[26]} {u_stress/agent_10/rx_vc0_cnt[27]} {u_stress/agent_10/rx_vc0_cnt[28]} {u_stress/agent_10/rx_vc0_cnt[29]} {u_stress/agent_10/rx_vc0_cnt[30]} {u_stress/agent_10/rx_vc0_cnt[31]}]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe2]
set_property port_width 32 [get_debug_ports u_ila_2/probe2]
connect_debug_port u_ila_2/probe2 [get_nets [list {u_stress/agent_10/tx_stall_cnt[0]} {u_stress/agent_10/tx_stall_cnt[1]} {u_stress/agent_10/tx_stall_cnt[2]} {u_stress/agent_10/tx_stall_cnt[3]} {u_stress/agent_10/tx_stall_cnt[4]} {u_stress/agent_10/tx_stall_cnt[5]} {u_stress/agent_10/tx_stall_cnt[6]} {u_stress/agent_10/tx_stall_cnt[7]} {u_stress/agent_10/tx_stall_cnt[8]} {u_stress/agent_10/tx_stall_cnt[9]} {u_stress/agent_10/tx_stall_cnt[10]} {u_stress/agent_10/tx_stall_cnt[11]} {u_stress/agent_10/tx_stall_cnt[12]} {u_stress/agent_10/tx_stall_cnt[13]} {u_stress/agent_10/tx_stall_cnt[14]} {u_stress/agent_10/tx_stall_cnt[15]} {u_stress/agent_10/tx_stall_cnt[16]} {u_stress/agent_10/tx_stall_cnt[17]} {u_stress/agent_10/tx_stall_cnt[18]} {u_stress/agent_10/tx_stall_cnt[19]} {u_stress/agent_10/tx_stall_cnt[20]} {u_stress/agent_10/tx_stall_cnt[21]} {u_stress/agent_10/tx_stall_cnt[22]} {u_stress/agent_10/tx_stall_cnt[23]} {u_stress/agent_10/tx_stall_cnt[24]} {u_stress/agent_10/tx_stall_cnt[25]} {u_stress/agent_10/tx_stall_cnt[26]} {u_stress/agent_10/tx_stall_cnt[27]} {u_stress/agent_10/tx_stall_cnt[28]} {u_stress/agent_10/tx_stall_cnt[29]} {u_stress/agent_10/tx_stall_cnt[30]} {u_stress/agent_10/tx_stall_cnt[31]}]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe3]
set_property port_width 32 [get_debug_ports u_ila_2/probe3]
connect_debug_port u_ila_2/probe3 [get_nets [list {u_stress/agent_10/rx_err_cnt[0]} {u_stress/agent_10/rx_err_cnt[1]} {u_stress/agent_10/rx_err_cnt[2]} {u_stress/agent_10/rx_err_cnt[3]} {u_stress/agent_10/rx_err_cnt[4]} {u_stress/agent_10/rx_err_cnt[5]} {u_stress/agent_10/rx_err_cnt[6]} {u_stress/agent_10/rx_err_cnt[7]} {u_stress/agent_10/rx_err_cnt[8]} {u_stress/agent_10/rx_err_cnt[9]} {u_stress/agent_10/rx_err_cnt[10]} {u_stress/agent_10/rx_err_cnt[11]} {u_stress/agent_10/rx_err_cnt[12]} {u_stress/agent_10/rx_err_cnt[13]} {u_stress/agent_10/rx_err_cnt[14]} {u_stress/agent_10/rx_err_cnt[15]} {u_stress/agent_10/rx_err_cnt[16]} {u_stress/agent_10/rx_err_cnt[17]} {u_stress/agent_10/rx_err_cnt[18]} {u_stress/agent_10/rx_err_cnt[19]} {u_stress/agent_10/rx_err_cnt[20]} {u_stress/agent_10/rx_err_cnt[21]} {u_stress/agent_10/rx_err_cnt[22]} {u_stress/agent_10/rx_err_cnt[23]} {u_stress/agent_10/rx_err_cnt[24]} {u_stress/agent_10/rx_err_cnt[25]} {u_stress/agent_10/rx_err_cnt[26]} {u_stress/agent_10/rx_err_cnt[27]} {u_stress/agent_10/rx_err_cnt[28]} {u_stress/agent_10/rx_err_cnt[29]} {u_stress/agent_10/rx_err_cnt[30]} {u_stress/agent_10/rx_err_cnt[31]}]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe4]
set_property port_width 4 [get_debug_ports u_ila_2/probe4]
connect_debug_port u_ila_2/probe4 [get_nets [list {u_stress/agent_10/rx_tdest_dbg[0]} {u_stress/agent_10/rx_tdest_dbg[1]} {u_stress/agent_10/rx_tdest_dbg[2]} {u_stress/agent_10/rx_tdest_dbg[3]}]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe5]
set_property port_width 32 [get_debug_ports u_ila_2/probe5]
connect_debug_port u_ila_2/probe5 [get_nets [list {u_stress/agent_10/rx_vc1_cnt[0]} {u_stress/agent_10/rx_vc1_cnt[1]} {u_stress/agent_10/rx_vc1_cnt[2]} {u_stress/agent_10/rx_vc1_cnt[3]} {u_stress/agent_10/rx_vc1_cnt[4]} {u_stress/agent_10/rx_vc1_cnt[5]} {u_stress/agent_10/rx_vc1_cnt[6]} {u_stress/agent_10/rx_vc1_cnt[7]} {u_stress/agent_10/rx_vc1_cnt[8]} {u_stress/agent_10/rx_vc1_cnt[9]} {u_stress/agent_10/rx_vc1_cnt[10]} {u_stress/agent_10/rx_vc1_cnt[11]} {u_stress/agent_10/rx_vc1_cnt[12]} {u_stress/agent_10/rx_vc1_cnt[13]} {u_stress/agent_10/rx_vc1_cnt[14]} {u_stress/agent_10/rx_vc1_cnt[15]} {u_stress/agent_10/rx_vc1_cnt[16]} {u_stress/agent_10/rx_vc1_cnt[17]} {u_stress/agent_10/rx_vc1_cnt[18]} {u_stress/agent_10/rx_vc1_cnt[19]} {u_stress/agent_10/rx_vc1_cnt[20]} {u_stress/agent_10/rx_vc1_cnt[21]} {u_stress/agent_10/rx_vc1_cnt[22]} {u_stress/agent_10/rx_vc1_cnt[23]} {u_stress/agent_10/rx_vc1_cnt[24]} {u_stress/agent_10/rx_vc1_cnt[25]} {u_stress/agent_10/rx_vc1_cnt[26]} {u_stress/agent_10/rx_vc1_cnt[27]} {u_stress/agent_10/rx_vc1_cnt[28]} {u_stress/agent_10/rx_vc1_cnt[29]} {u_stress/agent_10/rx_vc1_cnt[30]} {u_stress/agent_10/rx_vc1_cnt[31]}]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe6]
set_property port_width 32 [get_debug_ports u_ila_2/probe6]
connect_debug_port u_ila_2/probe6 [get_nets [list {u_stress/agent_10/tx_flit_cnt[0]} {u_stress/agent_10/tx_flit_cnt[1]} {u_stress/agent_10/tx_flit_cnt[2]} {u_stress/agent_10/tx_flit_cnt[3]} {u_stress/agent_10/tx_flit_cnt[4]} {u_stress/agent_10/tx_flit_cnt[5]} {u_stress/agent_10/tx_flit_cnt[6]} {u_stress/agent_10/tx_flit_cnt[7]} {u_stress/agent_10/tx_flit_cnt[8]} {u_stress/agent_10/tx_flit_cnt[9]} {u_stress/agent_10/tx_flit_cnt[10]} {u_stress/agent_10/tx_flit_cnt[11]} {u_stress/agent_10/tx_flit_cnt[12]} {u_stress/agent_10/tx_flit_cnt[13]} {u_stress/agent_10/tx_flit_cnt[14]} {u_stress/agent_10/tx_flit_cnt[15]} {u_stress/agent_10/tx_flit_cnt[16]} {u_stress/agent_10/tx_flit_cnt[17]} {u_stress/agent_10/tx_flit_cnt[18]} {u_stress/agent_10/tx_flit_cnt[19]} {u_stress/agent_10/tx_flit_cnt[20]} {u_stress/agent_10/tx_flit_cnt[21]} {u_stress/agent_10/tx_flit_cnt[22]} {u_stress/agent_10/tx_flit_cnt[23]} {u_stress/agent_10/tx_flit_cnt[24]} {u_stress/agent_10/tx_flit_cnt[25]} {u_stress/agent_10/tx_flit_cnt[26]} {u_stress/agent_10/tx_flit_cnt[27]} {u_stress/agent_10/tx_flit_cnt[28]} {u_stress/agent_10/tx_flit_cnt[29]} {u_stress/agent_10/tx_flit_cnt[30]} {u_stress/agent_10/tx_flit_cnt[31]}]]
create_debug_port u_ila_2 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_2/probe7]
set_property port_width 1 [get_debug_ports u_ila_2/probe7]
connect_debug_port u_ila_2/probe7 [get_nets [list u_stress/agent_10/test_done]]
create_debug_core u_ila_3 ila
set_property ALL_PROBE_SAME_MU true [get_debug_cores u_ila_3]
set_property ALL_PROBE_SAME_MU_CNT 1 [get_debug_cores u_ila_3]
set_property C_ADV_TRIGGER false [get_debug_cores u_ila_3]
set_property C_DATA_DEPTH 1024 [get_debug_cores u_ila_3]
set_property C_EN_STRG_QUAL false [get_debug_cores u_ila_3]
set_property C_INPUT_PIPE_STAGES 0 [get_debug_cores u_ila_3]
set_property C_TRIGIN_EN false [get_debug_cores u_ila_3]
set_property C_TRIGOUT_EN false [get_debug_cores u_ila_3]
set_property port_width 1 [get_debug_ports u_ila_3/clk]
connect_debug_port u_ila_3/clk [get_nets [list clk_gen/inst/clk_out5]]
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_3/probe0]
set_property port_width 4 [get_debug_ports u_ila_3/probe0]
connect_debug_port u_ila_3/probe0 [get_nets [list {u_stress/agent_11/rx_tdest_dbg[0]} {u_stress/agent_11/rx_tdest_dbg[1]} {u_stress/agent_11/rx_tdest_dbg[2]} {u_stress/agent_11/rx_tdest_dbg[3]}]]
create_debug_port u_ila_3 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_3/probe1]
set_property port_width 32 [get_debug_ports u_ila_3/probe1]
connect_debug_port u_ila_3/probe1 [get_nets [list {u_stress/agent_11/rx_vc0_cnt[0]} {u_stress/agent_11/rx_vc0_cnt[1]} {u_stress/agent_11/rx_vc0_cnt[2]} {u_stress/agent_11/rx_vc0_cnt[3]} {u_stress/agent_11/rx_vc0_cnt[4]} {u_stress/agent_11/rx_vc0_cnt[5]} {u_stress/agent_11/rx_vc0_cnt[6]} {u_stress/agent_11/rx_vc0_cnt[7]} {u_stress/agent_11/rx_vc0_cnt[8]} {u_stress/agent_11/rx_vc0_cnt[9]} {u_stress/agent_11/rx_vc0_cnt[10]} {u_stress/agent_11/rx_vc0_cnt[11]} {u_stress/agent_11/rx_vc0_cnt[12]} {u_stress/agent_11/rx_vc0_cnt[13]} {u_stress/agent_11/rx_vc0_cnt[14]} {u_stress/agent_11/rx_vc0_cnt[15]} {u_stress/agent_11/rx_vc0_cnt[16]} {u_stress/agent_11/rx_vc0_cnt[17]} {u_stress/agent_11/rx_vc0_cnt[18]} {u_stress/agent_11/rx_vc0_cnt[19]} {u_stress/agent_11/rx_vc0_cnt[20]} {u_stress/agent_11/rx_vc0_cnt[21]} {u_stress/agent_11/rx_vc0_cnt[22]} {u_stress/agent_11/rx_vc0_cnt[23]} {u_stress/agent_11/rx_vc0_cnt[24]} {u_stress/agent_11/rx_vc0_cnt[25]} {u_stress/agent_11/rx_vc0_cnt[26]} {u_stress/agent_11/rx_vc0_cnt[27]} {u_stress/agent_11/rx_vc0_cnt[28]} {u_stress/agent_11/rx_vc0_cnt[29]} {u_stress/agent_11/rx_vc0_cnt[30]} {u_stress/agent_11/rx_vc0_cnt[31]}]]
create_debug_port u_ila_3 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_3/probe2]
set_property port_width 32 [get_debug_ports u_ila_3/probe2]
connect_debug_port u_ila_3/probe2 [get_nets [list {u_stress/agent_11/tx_flit_cnt[0]} {u_stress/agent_11/tx_flit_cnt[1]} {u_stress/agent_11/tx_flit_cnt[2]} {u_stress/agent_11/tx_flit_cnt[3]} {u_stress/agent_11/tx_flit_cnt[4]} {u_stress/agent_11/tx_flit_cnt[5]} {u_stress/agent_11/tx_flit_cnt[6]} {u_stress/agent_11/tx_flit_cnt[7]} {u_stress/agent_11/tx_flit_cnt[8]} {u_stress/agent_11/tx_flit_cnt[9]} {u_stress/agent_11/tx_flit_cnt[10]} {u_stress/agent_11/tx_flit_cnt[11]} {u_stress/agent_11/tx_flit_cnt[12]} {u_stress/agent_11/tx_flit_cnt[13]} {u_stress/agent_11/tx_flit_cnt[14]} {u_stress/agent_11/tx_flit_cnt[15]} {u_stress/agent_11/tx_flit_cnt[16]} {u_stress/agent_11/tx_flit_cnt[17]} {u_stress/agent_11/tx_flit_cnt[18]} {u_stress/agent_11/tx_flit_cnt[19]} {u_stress/agent_11/tx_flit_cnt[20]} {u_stress/agent_11/tx_flit_cnt[21]} {u_stress/agent_11/tx_flit_cnt[22]} {u_stress/agent_11/tx_flit_cnt[23]} {u_stress/agent_11/tx_flit_cnt[24]} {u_stress/agent_11/tx_flit_cnt[25]} {u_stress/agent_11/tx_flit_cnt[26]} {u_stress/agent_11/tx_flit_cnt[27]} {u_stress/agent_11/tx_flit_cnt[28]} {u_stress/agent_11/tx_flit_cnt[29]} {u_stress/agent_11/tx_flit_cnt[30]} {u_stress/agent_11/tx_flit_cnt[31]}]]
create_debug_port u_ila_3 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_3/probe3]
set_property port_width 32 [get_debug_ports u_ila_3/probe3]
connect_debug_port u_ila_3/probe3 [get_nets [list {u_stress/agent_11/tx_stall_cnt[0]} {u_stress/agent_11/tx_stall_cnt[1]} {u_stress/agent_11/tx_stall_cnt[2]} {u_stress/agent_11/tx_stall_cnt[3]} {u_stress/agent_11/tx_stall_cnt[4]} {u_stress/agent_11/tx_stall_cnt[5]} {u_stress/agent_11/tx_stall_cnt[6]} {u_stress/agent_11/tx_stall_cnt[7]} {u_stress/agent_11/tx_stall_cnt[8]} {u_stress/agent_11/tx_stall_cnt[9]} {u_stress/agent_11/tx_stall_cnt[10]} {u_stress/agent_11/tx_stall_cnt[11]} {u_stress/agent_11/tx_stall_cnt[12]} {u_stress/agent_11/tx_stall_cnt[13]} {u_stress/agent_11/tx_stall_cnt[14]} {u_stress/agent_11/tx_stall_cnt[15]} {u_stress/agent_11/tx_stall_cnt[16]} {u_stress/agent_11/tx_stall_cnt[17]} {u_stress/agent_11/tx_stall_cnt[18]} {u_stress/agent_11/tx_stall_cnt[19]} {u_stress/agent_11/tx_stall_cnt[20]} {u_stress/agent_11/tx_stall_cnt[21]} {u_stress/agent_11/tx_stall_cnt[22]} {u_stress/agent_11/tx_stall_cnt[23]} {u_stress/agent_11/tx_stall_cnt[24]} {u_stress/agent_11/tx_stall_cnt[25]} {u_stress/agent_11/tx_stall_cnt[26]} {u_stress/agent_11/tx_stall_cnt[27]} {u_stress/agent_11/tx_stall_cnt[28]} {u_stress/agent_11/tx_stall_cnt[29]} {u_stress/agent_11/tx_stall_cnt[30]} {u_stress/agent_11/tx_stall_cnt[31]}]]
create_debug_port u_ila_3 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_3/probe4]
set_property port_width 2 [get_debug_ports u_ila_3/probe4]
connect_debug_port u_ila_3/probe4 [get_nets [list {u_stress/agent_11/state_dbg[0]} {u_stress/agent_11/state_dbg[1]}]]
create_debug_port u_ila_3 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_3/probe5]
set_property port_width 32 [get_debug_ports u_ila_3/probe5]
connect_debug_port u_ila_3/probe5 [get_nets [list {u_stress/agent_11/rx_err_cnt[0]} {u_stress/agent_11/rx_err_cnt[1]} {u_stress/agent_11/rx_err_cnt[2]} {u_stress/agent_11/rx_err_cnt[3]} {u_stress/agent_11/rx_err_cnt[4]} {u_stress/agent_11/rx_err_cnt[5]} {u_stress/agent_11/rx_err_cnt[6]} {u_stress/agent_11/rx_err_cnt[7]} {u_stress/agent_11/rx_err_cnt[8]} {u_stress/agent_11/rx_err_cnt[9]} {u_stress/agent_11/rx_err_cnt[10]} {u_stress/agent_11/rx_err_cnt[11]} {u_stress/agent_11/rx_err_cnt[12]} {u_stress/agent_11/rx_err_cnt[13]} {u_stress/agent_11/rx_err_cnt[14]} {u_stress/agent_11/rx_err_cnt[15]} {u_stress/agent_11/rx_err_cnt[16]} {u_stress/agent_11/rx_err_cnt[17]} {u_stress/agent_11/rx_err_cnt[18]} {u_stress/agent_11/rx_err_cnt[19]} {u_stress/agent_11/rx_err_cnt[20]} {u_stress/agent_11/rx_err_cnt[21]} {u_stress/agent_11/rx_err_cnt[22]} {u_stress/agent_11/rx_err_cnt[23]} {u_stress/agent_11/rx_err_cnt[24]} {u_stress/agent_11/rx_err_cnt[25]} {u_stress/agent_11/rx_err_cnt[26]} {u_stress/agent_11/rx_err_cnt[27]} {u_stress/agent_11/rx_err_cnt[28]} {u_stress/agent_11/rx_err_cnt[29]} {u_stress/agent_11/rx_err_cnt[30]} {u_stress/agent_11/rx_err_cnt[31]}]]
create_debug_port u_ila_3 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_3/probe6]
set_property port_width 32 [get_debug_ports u_ila_3/probe6]
connect_debug_port u_ila_3/probe6 [get_nets [list {u_stress/agent_11/rx_vc1_cnt[0]} {u_stress/agent_11/rx_vc1_cnt[1]} {u_stress/agent_11/rx_vc1_cnt[2]} {u_stress/agent_11/rx_vc1_cnt[3]} {u_stress/agent_11/rx_vc1_cnt[4]} {u_stress/agent_11/rx_vc1_cnt[5]} {u_stress/agent_11/rx_vc1_cnt[6]} {u_stress/agent_11/rx_vc1_cnt[7]} {u_stress/agent_11/rx_vc1_cnt[8]} {u_stress/agent_11/rx_vc1_cnt[9]} {u_stress/agent_11/rx_vc1_cnt[10]} {u_stress/agent_11/rx_vc1_cnt[11]} {u_stress/agent_11/rx_vc1_cnt[12]} {u_stress/agent_11/rx_vc1_cnt[13]} {u_stress/agent_11/rx_vc1_cnt[14]} {u_stress/agent_11/rx_vc1_cnt[15]} {u_stress/agent_11/rx_vc1_cnt[16]} {u_stress/agent_11/rx_vc1_cnt[17]} {u_stress/agent_11/rx_vc1_cnt[18]} {u_stress/agent_11/rx_vc1_cnt[19]} {u_stress/agent_11/rx_vc1_cnt[20]} {u_stress/agent_11/rx_vc1_cnt[21]} {u_stress/agent_11/rx_vc1_cnt[22]} {u_stress/agent_11/rx_vc1_cnt[23]} {u_stress/agent_11/rx_vc1_cnt[24]} {u_stress/agent_11/rx_vc1_cnt[25]} {u_stress/agent_11/rx_vc1_cnt[26]} {u_stress/agent_11/rx_vc1_cnt[27]} {u_stress/agent_11/rx_vc1_cnt[28]} {u_stress/agent_11/rx_vc1_cnt[29]} {u_stress/agent_11/rx_vc1_cnt[30]} {u_stress/agent_11/rx_vc1_cnt[31]}]]
create_debug_port u_ila_3 probe
set_property PROBE_TYPE DATA_AND_TRIGGER [get_debug_ports u_ila_3/probe7]
set_property port_width 1 [get_debug_ports u_ila_3/probe7]
connect_debug_port u_ila_3/probe7 [get_nets [list u_stress/agent_11/test_done]]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets clk_h00]
