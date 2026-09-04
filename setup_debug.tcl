# =============================================================================
# setup_debug.tcl
#
# สร้าง ILA debug core จากเน็ตที่ติด MARK_DEBUG ทั้งหมดในดีไซน์ที่สังเคราะห์แล้ว
# แทนการกด Tools > Set Up Debug ในหน้าจอ
#
#   open_run synth_1 ก่อน แล้ว
#   source D:/OpalFolder/MyOwnProject/FPGA/GALS_Packet-Based_Fabric/setup_debug.tcl
#
# ทำไมต้องมีไฟล์นี้ (gotcha 6):
#   ตัว wizard เขียน debug core ลง "target constraint file" ของ constrs_1
#   ซึ่งเคยชี้ไปที่ arty.xdc = ไฟล์ pin ทำให้ pin กับ debug core ปนกันอยู่ไฟล์เดียว
#   สลับ build ทีไรก็ต้องมานั่งแยกว่าบรรทัดไหนของใคร และมีรอบที่ debug core ของ
#   build ตัว stress ค้างอยู่ตอน build ตัว UART จน implementation พัง
#   ตอนนี้ target ชี้ไปที่ debug_auto.xdc แล้ว และสคริปต์นี้ทำให้ไม่ต้องพึ่ง GUI เลย
#   ทั้งกระบวนการจึงทำซ้ำได้และตรวจสอบได้จาก git
#
# การจัดกลุ่ม:
#   - แยก core ต่อโดเมนคล็อก (ILA หนึ่งตัวรับได้คล็อกเดียว)
#   - รวมเน็ตชื่อเดียวกันที่ต่างกันแค่ [n] ให้เป็น probe เดียวกว้างหลายบิต
#     เรียงตามดัชนี ไม่ใช่แยกเป็น probe ละบิต
# =============================================================================

if {[current_design -quiet] eq ""} {
    error "ยังไม่ได้เปิด design — ต้อง open_run synth_1 ก่อน"
}

set DEPTH 1024

# ---- 1. เก็บเน็ตที่ติด MARK_DEBUG
set dbg_nets [get_nets -hier -filter {MARK_DEBUG == 1}]
puts "setup_debug: เจอเน็ต MARK_DEBUG [llength $dbg_nets] เส้น"
if {[llength $dbg_nets] == 0} {
    error "ไม่มีเน็ต MARK_DEBUG เลย — สังเคราะห์ผิด top หรือ probe ถูกกวาดทิ้ง (gotcha 1)"
}

# ---- 2. หาคล็อกของแต่ละเน็ต
#
# get_clocks -of_objects <net> คืนค่าว่างกับเน็ตพวกนี้ทั้งหมด ใช้ไม่ได้
# วิธีที่ได้ผลคือไล่ไปหาตัวขับ:
#   - ต้อง -leaf เพราะเน็ตที่โผล่ที่ขอบ hierarchy จะมีตัวขับเป็นพินของโมดูล
#     (cell ref = ชื่อโมดูล) ซึ่งไม่มีขาคล็อก
#   - ถ้าตัวขับเป็น flip-flop ก็อ่านคล็อกจากขา C ได้ตรงๆ
#   - ถ้าเป็น LUT (เช่น ecc_single_err = |ecc_sbe ซึ่งเป็น combinational)
#     ต้องถอยกลับไปดูตัวขับของอินพุตอีกชั้น จนเจอ flip-flop
# จำกัดความลึกไว้กันวนไม่จบในลูป combinational
proc f_net_clock {n {depth 0}} {
    if {$depth > 8} { return "" }
    set dp [get_pins -quiet -leaf -of_objects $n -filter {DIRECTION == OUT}]
    if {$dp eq ""} { return "" }
    set cell [get_cells -quiet -of_objects $dp]
    if {$cell eq ""} { return "" }

    set ck [get_clocks -quiet -of_objects [get_pins -quiet -of_objects $cell -filter {IS_CLOCK}]]
    if {[llength $ck] == 1} { return [get_property NAME [lindex $ck 0]] }

    # ห้ามใส่ -leaf ตรงนี้: $cell เป็น leaf cell อยู่แล้ว พินของมันก็เป็น leaf pin
    # ใส่ -leaf กับ -of_objects <cell> แล้วได้ลิสต์ว่าง ทำให้การถอยกลับตายเงียบ
    # (อาการ: ธง ECC/dest_err สามเส้นหลุดจาก ILA ทั้งที่ทุกเส้นอื่นเข้าได้)
    foreach ip [get_pins -quiet -of_objects $cell -filter {DIRECTION == IN}] {
        set inet [get_nets -quiet -of_objects $ip]
        if {$inet eq ""} { continue }
        set r [f_net_clock $inet [expr {$depth + 1}]]
        if {$r ne ""} { return $r }
    }
    return ""
}

# แยกชื่อบัสกับดัชนี:  foo[12] -> base "foo", index 12
proc f_split_bus {nm} {
    if {[regexp {^(.*)\[(\d+)\]$} $nm -> base idx]} {
        return [list $base $idx]
    }
    return [list $nm 0]
}

# ---- 2a. ไล่หาคล็อกทีละเน็ตก่อน
array unset clk_of
array unset base_of
array unset idx_of
foreach n $dbg_nets {
    set nm [get_property NAME $n]
    lassign [f_split_bus $nm] base idx
    set base_of($nm) $base
    set idx_of($nm)  $idx
    set clk_of($nm)  [f_net_clock $n]
}

# ---- 2b. บิตที่หาคล็อกไม่ได้ ให้รับช่วงจากบิตอื่นในบัสเดียวกัน
#
# บัสหนึ่งบัสคือรีจิสเตอร์ชุดเดียวในโดเมนเดียว ถ้าบิต 0 หาคล็อกได้แต่บิต 1-3 ไม่ได้
# นั่นเป็นข้อจำกัดของการไล่ตามสายในสคริปต์ ไม่ใช่ว่าบิตพวกนั้นอยู่คนละโดเมนจริง
# ถ้าไม่รับช่วงกัน probe จะแคบลงเงียบๆ (เจอจริง: dest_err_node เหลือ 1 บิตจาก 4)
# ซึ่งเป็นความผิดพลาดแบบที่โปรเจกต์นี้โดนมาหลายรอบ — ILA ดูเหมือนทำงาน แต่ข้อมูลหาย
array unset bus_clks
foreach nm [array names clk_of] {
    if {$clk_of($nm) ne ""} {
        set b $base_of($nm)
        if {![info exists bus_clks($b)] ||
            [lsearch -exact $bus_clks($b) $clk_of($nm)] < 0} {
            lappend bus_clks($b) $clk_of($nm)
        }
    }
}

set inherited 0
foreach nm [array names clk_of] {
    if {$clk_of($nm) ne ""} { continue }
    set b $base_of($nm)
    if {[info exists bus_clks($b)] && [llength $bus_clks($b)] == 1} {
        set clk_of($nm) [lindex $bus_clks($b) 0]
        incr inherited
    }
}
if {$inherited > 0} {
    puts "setup_debug: $inherited บิตรับช่วงคล็อกจากบัสเดียวกัน (กัน probe แคบลงเงียบๆ)"
}

# ---- 2c. จัดกลุ่ม (คล็อก, ชื่อบัส) -> ดัชนี -> เน็ต
array unset grp
array unset noclk
foreach nm [array names clk_of] {
    if {$clk_of($nm) eq ""} {
        set noclk($nm) 0
        continue
    }
    lappend grp($clk_of($nm),$base_of($nm)) [list $idx_of($nm) $nm]
}

# ---- 3. ประกอบข้อความ xdc ตามลำดับที่ wizard ใช้
#
# ทำไมเขียนไฟล์เองไม่ใช้ save_constraints:
#   save_constraints เรียงบรรทัดผิดลำดับ — เขียนบล็อก probe0 ของทุก core ไว้
#   *ก่อน* บรรทัด create_debug_core ทั้งหมด พอ implementation อ่าน xdc ใหม่จึงเจอ
#   "Debug core 'u_ila_0' was not found" แล้วล้ม (เจอจริง รอบแรกพังทั้งรัน)
#   ลำดับที่ถูกคือ create core -> props -> clk -> probe0 -> create probe -> probe1
#   ผลพลอยได้: save_constraints จัดรูปไฟล์ *ทุกไฟล์* ใน constrs_1 ใหม่ ทำให้
#   line-continuation ในคอมเมนต์ของ timing.xdc เพี้ยน เขียนเองจึงไม่ไปแตะไฟล์อื่น
set clks_used {}
foreach k [array names grp] {
    set clk [lindex [split $k ,] 0]
    if {[lsearch -exact $clks_used $clk] < 0} { lappend clks_used $clk }
}
set clks_used [lsort $clks_used]

set L {}
lappend L "# debug_auto.xdc — สร้างโดย setup_debug.tcl ห้ามแก้ด้วยมือ"
lappend L "# arty.xdc เก็บแต่ pin/IO ไม่ให้ debug core มาปนอีก (gotcha 6)"
lappend L "# top = [get_property TOP [current_fileset]]"
lappend L ""

array unset clk_of_core
set core_idx 0
set total_probes 0
set total_bits 0
set hub_clk_net ""

foreach clk $clks_used {
    set core "u_ila_$core_idx"

    set clk_net [lindex [get_nets -quiet -of_objects [get_clocks $clk]] 0]
    if {$clk_net eq ""} {
        puts "setup_debug: WARNING ต่อขา clk ของ $core ไม่ได้ (คล็อก $clk) — ข้ามโดเมนนี้"
        continue
    }
    set clk_net_nm [get_property NAME $clk_net]

    lappend L "create_debug_core $core ila"
    lappend L "set_property ALL_PROBE_SAME_MU true \[get_debug_cores $core\]"
    lappend L "set_property ALL_PROBE_SAME_MU_CNT 1 \[get_debug_cores $core\]"
    lappend L "set_property C_ADV_TRIGGER false \[get_debug_cores $core\]"
    lappend L "set_property C_DATA_DEPTH $DEPTH \[get_debug_cores $core\]"
    lappend L "set_property C_EN_STRG_QUAL false \[get_debug_cores $core\]"
    lappend L "set_property C_INPUT_PIPE_STAGES 0 \[get_debug_cores $core\]"
    lappend L "set_property C_TRIGIN_EN false \[get_debug_cores $core\]"
    lappend L "set_property C_TRIGOUT_EN false \[get_debug_cores $core\]"
    lappend L "set_property port_width 1 \[get_debug_ports $core/clk\]"
    lappend L "connect_debug_port $core/clk \[get_nets \[list \{$clk_net_nm\}\]\]"

    set p 0
    foreach k [lsort [array names grp "$clk,*"]] {
        set ordered {}
        foreach e [lsort -integer -index 0 $grp($k)] {
            lappend ordered "\{[lindex $e 1]\}"
        }
        set w [llength $ordered]

        # probe0 มีมาพร้อม core อยู่แล้ว ตัวถัดไปต้อง create_debug_port ก่อน
        if {$p > 0} { lappend L "create_debug_port $core probe" }
        lappend L "set_property PROBE_TYPE DATA_AND_TRIGGER \[get_debug_ports $core/probe$p\]"
        lappend L "set_property port_width $w \[get_debug_ports $core/probe$p\]"
        lappend L "connect_debug_port $core/probe$p \[get_nets \[list [join $ordered " "]\]\]"

        incr p
        incr total_bits $w
    }
    incr total_probes $p
    set clk_of_core($core) [list $clk $p]

    if {$hub_clk_net eq ""} { set hub_clk_net $clk_net_nm }
    incr core_idx
}

# debug hub — wizard เขียนบล็อกนี้ท้ายไฟล์เสมอ ถ้าไม่มี implementation จะไม่รู้ว่า
# จะแขวน core ไว้กับคล็อกไหน
lappend L ""
lappend L "set_property C_CLK_INPUT_FREQ_HZ 300000000 \[get_debug_cores dbg_hub\]"
lappend L "set_property C_ENABLE_CLK_DIVIDER false \[get_debug_cores dbg_hub\]"
lappend L "set_property C_USER_SCAN_CHAIN 1 \[get_debug_cores dbg_hub\]"
lappend L "connect_debug_port dbg_hub/clk \[get_nets \{$hub_clk_net\}\]"

# ---- 4. รายงาน
puts "==================================================="
puts "setup_debug: $core_idx core / $total_probes probe / $total_bits บิต"
foreach core [lsort [array names clk_of_core]] {
    lassign $clk_of_core($core) clk p
    puts [format "   %-10s clk=%-34s probe=%d" $core $clk $p]
}
puts "   dbg_hub    clk=$hub_clk_net"
if {[array size noclk] > 0} {
    puts "---------------------------------------------------"
    puts "setup_debug: ข้าม [array size noclk] เน็ตที่หาคล็อกไม่ได้ (ไม่ได้เข้า ILA):"
    foreach nm [lsort [array names noclk]] { puts "   $nm" }
}
if {$total_bits != [llength $dbg_nets]} {
    puts "---------------------------------------------------"
    puts "setup_debug: WARNING เน็ต [llength $dbg_nets] เส้น แต่เข้า probe $total_bits บิต"
}
puts "==================================================="

# ---- 5. เขียนลง target constraint file (ต้องเป็น debug_auto.xdc ไม่ใช่ arty.xdc)
set tgt [get_property target_constrs_file [get_filesets constrs_1]]
if {[string match -nocase "*arty.xdc" $tgt]} {
    error "target constraint file ยังชี้ไปที่ arty.xdc (ไฟล์ pin) — gotcha 6 กลับมาแล้ว หยุดก่อน"
}
set fh [open $tgt w]
puts $fh [join $L "\n"]
close $fh
puts "setup_debug: เขียน [llength $L] บรรทัด -> $tgt"
puts "setup_debug: เสร็จ — ขั้นถัดไป launch_runs impl_1 -to_step write_bitstream"
