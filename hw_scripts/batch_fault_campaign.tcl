# Silicon fault-injection campaign on the stress build (arty_stress_top with vio_fault).
#   vivado -mode batch -source hw_scripts/batch_fault_campaign.tcl -tclargs <out_root> [modes]
# Programs once, then for each mode: VIO soft reset -> set mode+arm -> release reset ->
# wait for the window -> Trigger Immediately on every ILA -> CSV into <out_root>/mode_N/.
# One hw_server session for everything (no COM port involved, so no gotcha-9 resets).
#   mode 0 none | 1 kill tvalid | 2 tid 00 | 3 tid 11 | 4 tdest 0001 | 5 tdest 1000
set proj "D:/OpalFolder/MyOwnProject/FPGA/GALS_Packet-Based_Fabric"
set d    "$proj/GALS_Packet-Based_Fabric.runs/impl_1"
set out  [lindex $argv 0]
set modes [expr {[llength $argv] > 1 ? [lrange $argv 1 end] : {0 1 2 3 4 5}}]
file mkdir $out
open_hw_manager; connect_hw_server; open_hw_target
set dev [lindex [get_hw_devices xc7a100t*] 0]; current_hw_device $dev
set_property PROGRAM.FILE     "$d/arty_stress_top.bit" $dev
set_property PROBES.FILE      "$d/arty_stress_top.ltx" $dev
set_property FULL_PROBES.FILE "$d/arty_stress_top.ltx" $dev
program_hw_devices $dev
refresh_hw_device $dev
set vio  [lindex [get_hw_vios -of_objects $dev] 0]
# probes are named after the nets they connect to, not the IP port names
set pout [lindex [get_hw_probes -of_objects $vio -filter {TYPE == vio_output}] 0]
set pin  [lindex [get_hw_probes -of_objects $vio -filter {TYPE == vio_input}]  0]
puts "VIO probes: out=$pout in=$pin"
proc vio_set {v} { global vio pout; set_property OUTPUT_VALUE [format "%02X" $v] $pout; commit_hw_vio $vio }
proc vio_get {}  { global vio pin;  refresh_hw_vio $vio; return [get_property INPUT_VALUE $pin] }
set ilas [get_hw_ilas -of_objects $dev]
puts "ILAS [llength $ilas]  VIO $vio"
foreach m $modes {
    set word [expr {($m << 2) | 0x02}]
    vio_set [expr {$word | 0x01}]     ;# reset held, mode + arm set
    after 200
    vio_set $word                     ;# release reset: run starts, injector fires at 2^20 cycles
    after 2000                        ;# window 235 ms + drain; leave margin
    set st [vio_get]
    file mkdir "$out/mode_$m"
    set i 0
    foreach ila $ilas {
        run_hw_ila $ila -trigger_now; wait_on_hw_ila $ila
        write_hw_ila_data -csv_file "$out/mode_$m/iladata_$i.csv" [upload_hw_ila_data $ila] -force
        incr i
    }
    puts "MODE $m  vio_in=$st  (bits: fired active tid_err dest_err ecc_dbe any_fail pass2 pass1)"
}
vio_set 0x00
close_hw_manager
puts "CAMPAIGN_DONE"
