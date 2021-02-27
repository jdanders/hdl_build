if { [file exists $::env(ABSPATH_SDC_FILE)] == 1} {
    set_global_assignment -name SDC_ENTITY_FILE $::env(ABSPATH_SDC_FILE) -entity $::env(TOP) -no_sdc_promotion
}
set_global_assignment -name SDC_FILE $::env(HDL_BUILD_PATH)/intel/jtag.sdc
