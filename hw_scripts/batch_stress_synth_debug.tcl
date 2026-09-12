# Session A: synth + scripted Set Up Debug for the stress build, then exit.
#   vivado -mode batch -source hw_scripts/batch_stress_synth_debug.tcl
# Implementation must run in a NEW session (hw_scripts/batch_impl.tcl); see HANDOFF gotcha 6.
# To build an ECC fault-injection bitstream change the verilog_define line to {ECC_INJECT_SBE} or
# {ECC_INJECT_DBE}, and clear it again afterwards.
set proj "D:/OpalFolder/MyOwnProject/FPGA/GALS_Packet-Based_Fabric"
open_project "$proj/GALS_Packet-Based_Fabric.xpr"
set_property verilog_define {} [current_fileset]
set PATTERN 1
set VC_MODE 2
source "$proj/setup_stress_build.tcl"
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} { error "synth failed" }
source "$proj/setup_debug.tcl"
close_project
puts "SESSION_A_DONE"
