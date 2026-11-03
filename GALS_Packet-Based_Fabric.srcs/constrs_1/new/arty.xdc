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





