if { [file exists $::env(ABSPATH_SDC_FILE)] == 1} {
    set_global_assignment -name SDC_ENTITY_FILE $::env(ABSPATH_SDC_FILE) -entity $::env(TOP) -no_sdc_promotion
}
set_global_assignment -name SDC_FILE $::env(SRC_BASE_DIR)/ip_cores/jtag.sdc
