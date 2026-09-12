# Session C: program the Arty, wait for the run to finish, Trigger Immediately on every ILA, export CSV
# usage: vivado -mode batch -source hw_scripts/batch_program_capture.tcl -tclargs <out_dir> <top> [noprog]
#   then: python analyze_ila.py <out_dir>   (stress)  /  python hw_scripts/read_ila_flags.py <out_dir>  (uart)
set proj "D:/OpalFolder/MyOwnProject/FPGA/GALS_Packet-Based_Fabric"
set out  [lindex $argv 0]
set top  [lindex $argv 1]
set noprog [expr {[lindex $argv 2] eq "noprog"}]
file mkdir $out
set d "$proj/GALS_Packet-Based_Fabric.runs/impl_1"
open_hw_manager
connect_hw_server
open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]
current_hw_device $dev
set_property PROGRAM.FILE     "$d/$top.bit" $dev
set_property PROBES.FILE      "$d/$top.ltx" $dev
set_property FULL_PROBES.FILE "$d/$top.ltx" $dev
if {!$noprog} { program_hw_devices $dev }
refresh_hw_device $dev
set ilas [get_hw_ilas -of_objects $dev]
puts "ILAS [llength $ilas]: $ilas"
# window 2^24 cycles at 71.43 MHz = 235 ms, plus drain; wait well past it
after 3000
set i 0
foreach ila $ilas {
    run_hw_ila $ila -trigger_now
    wait_on_hw_ila $ila
    set data [upload_hw_ila_data $ila]
    write_hw_ila_data -csv_file "$out/iladata_$i.csv" $data -force
    puts "CSV $i <- $ila probes=[llength [get_hw_probes -of_objects $ila]]"
    incr i
}
close_hw_manager
puts "SESSION_C_DONE"
