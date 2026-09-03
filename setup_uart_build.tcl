# =============================================================================
# setup_uart_build.tcl
#
# ตั้ง project ให้ build ตัว UART (arty_gals_noc_wrapper) แล้วสังเคราะห์
#   source D:/OpalFolder/MyOwnProject/FPGA/GALS_Packet-Based_Fabric/setup_uart_build.tcl
#
# คู่กับ setup_stress_build.tcl ซึ่ง build ตัว arty_stress_top
# สลับไปมาได้ด้วยการ source สคริปต์คนละตัว
#
# ที่มา: build นี้ค้างมานาน ไม่ได้ประกอบใหม่ตั้งแต่ debug.xdc ถูกถอดออก
#   (HANDOFF gotcha 5) และ probe ทั้งหมดใน loopback_node_agent / uart_noc_host
#   ถูกครอบด้วย `ifdef DEBUG_BUILD ที่ไม่มีใครนิยาม จึงไม่มี instrumentation เลย
#   ตอนนี้เอา ifdef ออกแล้ว และใส่ dont_touch คู่ mark_debug ให้ probe รอดจริง
# =============================================================================

set proj_dir "D:/OpalFolder/MyOwnProject/FPGA/GALS_Packet-Based_Fabric"
set src_dir  "$proj_dir/GALS_Packet-Based_Fabric.srcs/sources_1/new"

# ---- 1. ไฟล์ที่ build นี้ต้องใช้ (ตัว stress ไม่ได้ใช้สามตัวนี้)
foreach f {arty_gals_noc_wrapper.sv uart_noc_host.sv uart_transceiver.sv
           loopback_node_agent.sv} {
    set ff [get_files -quiet "$src_dir/$f"]
    if {$ff eq ""} {
        add_files -norecurse -fileset sources_1 "$src_dir/$f"
        puts "INFO: added $f"
    }
    set_property file_type SystemVerilog [get_files "$src_dir/$f"]
}

# ---- 2. ตั้ง top
set_property top arty_gals_noc_wrapper [current_fileset]
set_property top_auto_set 0 [current_fileset]
puts "INFO: top = [get_property top [current_fileset]]"

# ---- 3. สังเคราะห์ใหม่
set_property AUTO_INCREMENTAL_CHECKPOINT 0 [get_runs synth_1]
reset_run synth_1
launch_runs synth_1 -jobs 8
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: synthesis failed — ดู $proj_dir/GALS_Packet-Based_Fabric.runs/synth_1/runme.log"
    return
}

open_run synth_1 -name synth_1

set dbg_nets [get_nets -hier -filter {MARK_DEBUG == 1}]
puts "==================================================="
puts "MARK_DEBUG nets ที่รอดมา: [llength $dbg_nets]"
puts "==================================================="
puts "คาดว่าจะได้ราว 440 เส้น:"
puts "  296 = mon_* ของ gals_noc_top (256) + ตัวนับ ECC (40)"
puts "  144 = loopback_node_agent 37 x 3 ตัว + uart_noc_host 33"
puts "ถ้าได้ 296 แปลว่า probe ของ loopback/uart ยังไม่เข้า"
puts "   -> เช็คว่ายังมี \\`ifdef DEBUG_BUILD ค้างอยู่ในไฟล์ไหม"
puts ""
puts "\[!\] arty.xdc ยังมี debug core ของ build ตัว stress ค้างอยู่"
puts "    (u_stress/agent_* ซึ่งไม่มีในดีไซน์นี้) — gotcha 6"
puts "    synthesis ไม่สนใจบรรทัดพวกนั้น แต่ implementation จะพัง"
puts "    ต้อง Tools > Set Up Debug ใหม่ก่อน Run Implementation เสมอ"
puts "    Set Up Debug จะเขียนทับ core เก่าให้เอง"
puts ""
puts "ขั้นถัดไป: Tools > Set Up Debug  ->  Run Implementation"
