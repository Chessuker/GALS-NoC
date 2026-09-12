# Session B: implementation + bitstream. MUST be a fresh Vivado session so debug_auto.xdc is re-read.
#   vivado -mode batch -source hw_scripts/batch_impl.tcl -tclargs <top>   (arty_stress_top | arty_gals_noc_wrapper)
set proj "D:/OpalFolder/MyOwnProject/FPGA/GALS_Packet-Based_Fabric"
set top [lindex $argv 0]
open_project "$proj/GALS_Packet-Based_Fabric.xpr"
reset_run impl_1
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
puts "IMPL_PROGRESS [get_property PROGRESS [get_runs impl_1]] STATUS [get_property STATUS [get_runs impl_1]]"
set d "$proj/GALS_Packet-Based_Fabric.runs/impl_1"
puts "BIT [file exists $d/$top.bit]  LTX [file exists $d/$top.ltx]"
close_project
puts "SESSION_B_DONE"
