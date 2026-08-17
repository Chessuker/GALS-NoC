# debug build
set_property verilog_define {DEBUG_BUILD} [get_filesets sources_1]
# release build
set_property verilog_define {} [get_filesets sources_1]
# enable debug xdc
set_property is_enabled false [get_files debug.xdc]

# save report_cdc
report_cdc -details -file report_cdc.rpt
# save report_clock_interaction
report_clock_interaction -file report_clock_interaction.rpt

report_utilization -hierarchical -file utilization_hierarchical.rpt