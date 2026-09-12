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

# ---- CDC report on the routed design. The five clocks are declared asynchronous in
# timing.xdc, so STA never checks a path between domains; this is the only tool-side check
# that every crossing goes through a recognised synchroniser. README suggested it; nothing
# ran it before 2026-09-12. Files land next to the bitstream (gitignored); the summary
# lines are printed so they end up in the session log.
open_run impl_1
report_cdc -details -file "$d/${top}_cdc.rpt"
report_clock_interaction -file "$d/${top}_clock_interaction.rpt"
set fh [open "$d/${top}_cdc.rpt" r]; set txt [read $fh]; close $fh
# summary table rows look like:  CDC-10  Critical      5  Combinational logic ...
array set cdc {Critical 0 Warning 0 Info 0}
foreach {m sev n} [regexp -all -inline -line {^CDC-\d+\s+(Critical|Warning|Info)\s+(\d+)} $txt] {
    incr cdc($sev) $n
}
foreach sev {Critical Warning Info} { puts "CDC_$sev $cdc($sev)" }
if {$cdc(Critical) > 0} { puts "CDC_CRITICAL_PRESENT: read $d/${top}_cdc.rpt before trusting this bitstream" }
puts "CDC_REPORT $d/${top}_cdc.rpt"
close_project
puts "SESSION_B_DONE"
