# =============================================================================
# setup_stress_build.tcl
#
# สลับ project ไปเป็น "stress build" แล้วสังเคราะห์ใหม่
#   source D:/OpalFolder/MyOwnProject/FPGA/GALS_Packet-Based_Fabric/setup_stress_build.tcl
#
# กลับไป UART build ได้ด้วย:
#   set_property top arty_gals_noc_wrapper [current_fileset]
#   reset_run synth_1
#
# ไฟล์สำรองอยู่ที่ backup_20260804/
# =============================================================================

set proj_dir "D:/OpalFolder/MyOwnProject/FPGA/GALS_Packet-Based_Fabric"
set src_dir  "$proj_dir/GALS_Packet-Based_Fabric.srcs/sources_1/new"

# ---- 1. เพิ่มไฟล์ top ตัวใหม่เข้า project (ถ้ายังไม่มี)
set new_top "$src_dir/arty_stress_top.sv"
if {[lsearch -exact [get_files -quiet *arty_stress_top.sv] $new_top] < 0} {
    add_files -norecurse -fileset sources_1 $new_top
    puts "INFO: added arty_stress_top.sv"
} else {
    puts "INFO: arty_stress_top.sv already in project"
}
set_property file_type SystemVerilog [get_files $new_top]

# ---- 2. บังคับให้ไฟล์ที่แก้ไปแล้วถูกอ่านเป็น SystemVerilog
foreach f {traffic_node_agent.sv noc_stress_tester.sv} {
    set ff [get_files -quiet "$src_dir/$f"]
    if {$ff ne ""} { set_property file_type SystemVerilog [get_files $ff] }
}

# ---- 3. ตั้ง top ใหม่
set_property top arty_stress_top [current_fileset]
set_property top_auto_set 0 [current_fileset]
puts "INFO: top = [get_property top [current_fileset]]"

# ---- 4. เอา debug.xdc เก่าออกจาก project
#         (เนื้อในอ้าง echo_01/echo_10/echo_11 ของ UART build ซึ่งไม่มีใน top นี้)
#         ลบออกจาก fileset เฉยๆ ไฟล์ยังอยู่บนดิสก์ + มีสำเนาใน backup_20260804/
set dbg [get_files -quiet *debug.xdc]
if {$dbg ne ""} {
    remove_files -fileset constrs_1 $dbg
    puts "INFO: removed debug.xdc from constrs_1 (file kept on disk)"
}

# ---- 5. DEBUG_BUILD ไม่จำเป็นสำหรับ top นี้ แต่ปล่อยไว้ก็ไม่เสียหาย
#         (traffic_node_agent ไม่ได้ใช้ `ifdef เหมือน loopback_node_agent)

# ---- 6. สังเคราะห์ใหม่แบบสะอาด ไม่ใช้ incremental checkpoint เดิม
set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs synth_1]
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: synthesis failed — ดู log ที่ $proj_dir/GALS_Packet-Based_Fabric.runs/synth_1/runme.log"
    return
}

# ---- 7. เปิด netlist แล้วนับ net ที่ mark_debug รอดมา
open_run synth_1 -name synth_1
set dbg_nets [get_nets -hier -filter {MARK_DEBUG == 1}]
puts "==================================================="
puts "MARK_DEBUG nets ที่รอดมา: [llength $dbg_nets]"
puts "==================================================="
set buses {}
foreach x $dbg_nets {
    regsub {\[\d+\]$} $x {} base
    lappend buses $base
}
foreach n [lsort -unique $buses] { puts "  $n" }
puts ""
puts "ถ้าเลขข้างบนมากกว่า 0 -> ไปที่ Tools > Set Up Debug ได้เลย"
