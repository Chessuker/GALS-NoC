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
puts "คาดว่าจะได้ 463 เส้น:"
puts "  296 = mon_* ของ gals_noc_top (256) + ตัวนับ ECC (40)"
puts "   20 = ตัวนับปลายทางนอกกระดาน (dest_err_node 4 + dest_err_cnt 16)"
puts "  144 = loopback_node_agent 37 x 3 ตัว + uart_noc_host 33"
puts "    3 = ธง ecc_sbe/ecc_dbe/dest_err ที่ต่อขึ้นมาให้ ILA เห็นใน top นี้"
puts "ถ้าได้ 296 แปลว่า probe ของ loopback/uart ยังไม่เข้า"
puts ""
puts "ขั้นถัดไป (ไม่ต้องใช้หน้าจอแล้ว — gotcha 6 แก้ที่ต้นเหตุไปแล้ว):"
puts "    open_run synth_1"
puts "    source \$proj_dir/setup_debug.tcl"
puts "    launch_runs impl_1 -to_step write_bitstream -jobs 8"
puts ""
puts "target constraint file ของ constrs_1 ชี้ไป debug_auto.xdc แล้ว debug core"
puts "จึงไม่ปนกับ pin ใน arty.xdc อีก สลับ build ได้โดยไม่ต้องแยกบรรทัดเอง"
