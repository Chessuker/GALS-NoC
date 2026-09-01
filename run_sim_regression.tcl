# =============================================================================
# run_sim_regression.tcl
#
# คืน tb_noc_mesh_2x2_gals กลับเข้า project แล้วรัน regression ทั้ง 6 เทสต์
#   source D:/OpalFolder/MyOwnProject/FPGA/GALS_Packet-Based_Fabric/run_sim_regression.tcl
#
# baseline ของวันที่ 2026-07-11 (Matched=34 Mismatched=0 Pending=0) เก็บไว้ที่
#   backup_20260804/sim_baseline_20260711/simulate.log
#
# เหตุผลที่ต้องรันใหม่: RTL แทบทั้ง datapath ถูกแก้หลัง 07-11
#   router_5port_mesh_vc (07-16), vc_port_arbiter (07-14),
#   packet_arbiter (07-26), vc_input_buffer (07-14), noc_mesh_2x2_vc (07-18)
# ซึ่งเป็นโมดูลที่ Test 2/4/5 มีไว้พิสูจน์โดยตรง
# =============================================================================

set proj_dir "D:/OpalFolder/MyOwnProject/FPGA/GALS_Packet-Based_Fabric"
set src_dir  "$proj_dir/GALS_Packet-Based_Fabric.srcs/sources_1/new"
set tb_file  "$src_dir/tb_noc_mesh_2x2_gals.sv"
set sim_log  "$proj_dir/GALS_Packet-Based_Fabric.sim/sim_1/behav/xsim/simulate.log"
set log_dir  "$proj_dir/sim_logs"

# เก็บบรรทัดสรุปไว้ เพื่อเขียนลงไฟล์ตอนจบ (ไม่เปิด file handle ค้างไว้
# เพราะสคริปต์มีทาง return กลางคันหลายจุด)
set sum_lines {}
proc logput {msg} {
    global sum_lines
    puts $msg
    lappend sum_lines $msg
}

if {![file exists $tb_file]} {
    puts "ERROR: ไม่พบ $tb_file"
    puts "       คัดลอกมาจาก $src_dir/old/tb_noc_mesh_2x2_gals.sv ก่อน"
    return
}

# ---- 1. เพิ่ม TB เข้า fileset sim_1 (ถ้ายังไม่มี)
if {[lsearch -exact [get_files -quiet -of [get_filesets sim_1] *tb_noc_mesh_2x2_gals.sv] $tb_file] < 0} {
    add_files -fileset sim_1 -norecurse $tb_file
    puts "INFO: added tb_noc_mesh_2x2_gals.sv to sim_1"
} else {
    puts "INFO: tb already in sim_1"
}
set_property file_type SystemVerilog [get_files $tb_file]

# ---- 2. ตั้ง top ของ sim_1
set_property top tb_noc_mesh_2x2_gals [get_filesets sim_1]
set_property top_lib xil_defaultlib   [get_filesets sim_1]

# ---- 3. สำคัญมาก: ปล่อยให้รันจนถึง $finish
#         ค่า default คือ 1000ns ซึ่งจบแค่กลาง Test 1 เท่านั้น
#         TB ตัวนี้ $finish ที่ ~5.29 ms
set_property -name {xsim.simulate.runtime} -value {all} -objects [get_filesets sim_1]

# ---- 3b. เลือกชุดนาฬิกา
#         set HW_CLOCKS 1 ; source ...  = อัตราส่วนเดียวกับบอร์ด Arty
#         ไม่ตั้งค่า                     = ค่าเดิมของ TB (เทียบ baseline ก.ค. ได้)
if {![info exists HW_CLOCKS]} { set HW_CLOCKS 0 }
if {![info exists HS_VC_ALT]} { set HS_VC_ALT 0 }
# SIM_DEBUG 1 = เปิด $display ใน vc_port_arbiter (override trigger/release)
#               ใช้ไล่ดูว่า vc0_override ค้างหรือไม่ตอน NoC หยุดส่ง
if {![info exists SIM_DEBUG]} { set SIM_DEBUG 0 }

set sim_defs {}
if {$HW_CLOCKS} {
    lappend sim_defs HW_CLOCKS
    set clk_desc "HW-matched : NoC 80 MHz, sink 100 MHz, senders 71.4/83.3/71.4 MHz"
} else {
    set clk_desc "TB default : NoC 250 MHz, sink 500 MHz, senders 125/333/100 MHz"
}
if {$HS_VC_ALT} {
    lappend sim_defs HS_VC_ALT
    set vc_desc  "alternating VC0/VC1 - เหมือนบอร์ด (traffic_node_agent VC_MODE=2)"
} else {
    set vc_desc  "VC0 only - แยก packet_arbiter ออกมาทดสอบตัวเดียว"
}
if {$SIM_DEBUG} {
    lappend sim_defs SIM_DEBUG
    set dbg_desc "on - vc_port_arbiter override tracing"
} else {
    set dbg_desc "off"
}
set_property verilog_define $sim_defs [get_filesets sim_1]

# ชื่อไฟล์ล็อกบอก config ในตัว จะได้ไม่ทับกันเวลารันหลายแบบ
file mkdir $log_dir
set tag [expr {$HW_CLOCKS ? "hwclk" : "tbclk"}]
if {$HS_VC_ALT} { append tag "_vcalt" }
if {$SIM_DEBUG} { append tag "_dbg" }
set stamp   [clock format [clock seconds] -format "%Y%m%d_%H%M%S"]
set out_log "$log_dir/regress_${tag}_${stamp}.log"

puts "INFO: sim top      = [get_property top [get_filesets sim_1]]"
puts "INFO: clocks       = $clk_desc"
puts "INFO: Test6 VC     = $vc_desc"
puts "INFO: SIM_DEBUG    = $dbg_desc"
puts "INFO: sim runtime  = [get_property xsim.simulate.runtime [get_filesets sim_1]]"

# ---- 4. ลบ log เก่าทิ้ง เพื่อไม่ให้อ่านผลรันก่อนหน้าปนมา
if {[file exists $sim_log]} { file delete -force $sim_log }

# ---- 5. รัน
puts "INFO: launching behavioral simulation ..."
launch_simulation

# ---- 6. รอจน $finish โผล่ใน log (สูงสุด ~5 นาที)
set waited 0
while {$waited < 300} {
    if {[file exists $sim_log]} {
        set fh [open $sim_log r]; set txt [read $fh]; close $fh
        if {[string match "*\$finish called*" $txt]} { break }
    }
    after 2000
    incr waited 2
}

if {![file exists $sim_log]} {
    puts "ERROR: ไม่มี simulate.log — ดู compile.log / elaborate.log ในโฟลเดอร์เดียวกัน"
    return
}

set fh [open $sim_log r]; set txt [read $fh]; close $fh

# ---- 7. สรุปผล
logput ""
logput "==================================================="
logput " SIM REGRESSION RESULT"
logput "==================================================="

# หมายเหตุ: TB พิมพ์ "Test 3 Finished" ซ้ำสองครั้ง (บล็อกซ้ำใน source)
# จึงต้องนับเลขเทสต์แบบไม่ซ้ำ ไม่ใช่นับจำนวนบรรทัด
set seen {}
foreach {whole num} [regexp -all -inline {Test (\d) Finished} $txt] {
    if {[lsearch -exact $seen $num] < 0} { lappend seen $num }
}
set seen [lsort $seen]
set finished [llength $seen]
logput "  tests finished        : $finished / 6   (เทสต์ที่จบ: $seen)"

set totals {}
foreach {whole m mm p} [regexp -all -inline {TOTAL: Matched=(\d+) Mismatched=(\d+) Pending=(\d+)} $txt] {
    lappend totals [list $m $mm $p]
}
if {[llength $totals] == 0} {
    logput "  scoreboard            : ไม่พบบรรทัด TOTAL — เทสต์อาจไม่ได้จบ"
} else {
    set last [lindex $totals end]
    lassign $last m mm p
    logput "  final scoreboard      : Matched=$m  Mismatched=$mm  Pending=$p"
    logput "  baseline              : Mismatched=0  Pending=0  (Matched แปรได้ เพราะ Test 6"
    logput "                          ยิงตามเวลา ไม่ได้ตามจำนวนแพ็กเกจคงที่)"
    if {$mm == 0 && $p == 0 && $finished == 6} {
        logput ""
        logput "  >>> PASS — ตรงกับ baseline"
    } else {
        logput ""
        logput "  >>> FAIL — มี mismatch/pending หรือเทสต์ไม่ครบ"
        logput "      โมดูลที่เปลี่ยนหลัง baseline และน่าสงสัยที่สุด:"
        logput "        router_5port_mesh_vc.sv  vc_port_arbiter.sv"
        logput "        packet_arbiter.sv        vc_input_buffer.sv"
    }
}

# ระวัง: อย่าจับคำว่า "Mismatch" ลอยๆ เพราะบรรทัด "Mismatched=0" ก็จะติดมาด้วย
set errs [regexp -all {\[SB-FAIL\]|Mismatched=[1-9]|\[Error\]|\[Timeout\]} $txt]
logput "  error markers in log  : $errs"
logput "==================================================="
logput "  full log: $sim_log"
logput "  baseline: $proj_dir/backup_20260804/sim_baseline_20260711/simulate.log"

# ---- 8. บันทึกลงไฟล์: header + log เต็มของ xsim + สรุป  ในไฟล์เดียวจบ
set fh_out [open $out_log w]
puts $fh_out "==================================================="
puts $fh_out " GALS NoC - simulation regression"
puts $fh_out " date     : [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
puts $fh_out " clocks   : $clk_desc"
puts $fh_out " Test6 VC : $vc_desc"
puts $fh_out " defines  : [expr {[llength $sim_defs] ? $sim_defs : "(none)"}]"
puts $fh_out "==================================================="
puts $fh_out ""
puts $fh_out $txt
puts $fh_out ""
foreach l $sum_lines { puts $fh_out $l }
close $fh_out

puts ""
puts "  >>> saved to: $out_log"
