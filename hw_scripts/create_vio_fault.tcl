# One-off: add the VIO core that drives fault_injector on the stress build.
#   vivado -mode batch -source hw_scripts/create_vio_fault.tcl
# probe_out0[7:0] : [0] soft reset (active high)  [1] arm  [5:2] fault mode  [7:6] unused
# probe_in0[7:0]  : {fault_fired, fault_active, tid_err_s, dest_err_s, ecc_dbe_s, any_fail, pass_g2, pass_g1}
set proj "D:/OpalFolder/MyOwnProject/FPGA/GALS_Packet-Based_Fabric"
open_project "$proj/GALS_Packet-Based_Fabric.xpr"
if {[get_ips -quiet vio_fault] eq ""} {
    create_ip -name vio -vendor xilinx.com -library ip -module_name vio_fault
    set_property -dict [list \
        CONFIG.C_NUM_PROBE_OUT {1} CONFIG.C_PROBE_OUT0_WIDTH {8} CONFIG.C_PROBE_OUT0_INIT_VAL {0x00} \
        CONFIG.C_NUM_PROBE_IN {1}  CONFIG.C_PROBE_IN0_WIDTH {8} \
        CONFIG.C_EN_PROBE_IN_ACTIVITY {0}] [get_ips vio_fault]
    generate_target all [get_ips vio_fault]
    puts "VIO_CREATED [get_property IP_FILE [get_ips vio_fault]]"
} else {
    puts "VIO_EXISTS"
}
close_project
