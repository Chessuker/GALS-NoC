# UART build: program, then hold one hw_server session open while the PC drives the port,
# capturing every ILA at each handshake point. Needed because opening the COM port resets
# the FPGA (HANDOFF gotcha 9): captures taken in separate sessions describe different runs.
#   vivado -mode batch -source hw_scripts/batch_uart_session.tcl -tclargs <out_root> [noprog]
# Protocol (files in <out_root>): script writes ready_<tag>, waits for go_<tag>; tags a,b,c.
#   a = fresh after programming, b = after positive round-trip, c = after negative (tid=00)
# Driver side (bash): wait for ready_a; python uart_roundtrip.py pos; touch go_b; wait ready_b;
#   python uart_roundtrip.py neg; touch go_c; then read <out_root>/cap_* with read_ila_flags.py
set proj "D:/OpalFolder/MyOwnProject/FPGA/GALS_Packet-Based_Fabric"
set d    "$proj/GALS_Packet-Based_Fabric.runs/impl_1"
set out  [lindex $argv 0]
set noprog [expr {[lindex $argv 1] eq "noprog"}]
file mkdir $out
open_hw_manager; connect_hw_server; open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]; current_hw_device $dev
set_property PROGRAM.FILE     "$d/arty_gals_noc_wrapper.bit" $dev
set_property PROBES.FILE      "$d/arty_gals_noc_wrapper.ltx" $dev
set_property FULL_PROBES.FILE "$d/arty_gals_noc_wrapper.ltx" $dev
if {!$noprog} { program_hw_devices $dev }
refresh_hw_device $dev
proc grab {dev tag out} {
    file mkdir "$out/cap_$tag"
    set i 0
    foreach ila [get_hw_ilas -of_objects $dev] {
        run_hw_ila $ila -trigger_now; wait_on_hw_ila $ila
        write_hw_ila_data -csv_file "$out/cap_$tag/iladata_$i.csv" [upload_hw_ila_data $ila] -force
        incr i
    }
    puts "GRAB $tag"
}
grab $dev a $out
close [open "$out/ready_a" w]
while {![file exists "$out/go_b"]} { after 200 }
grab $dev b $out
close [open "$out/ready_b" w]
while {![file exists "$out/go_c"]} { after 200 }
grab $dev c $out
close_hw_manager
puts "UART_SESSION_DONE"
