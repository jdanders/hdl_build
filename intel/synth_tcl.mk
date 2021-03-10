#-*- makefile -*-

# This is needed for subst command below
define newline


endef


define global_tcl
project_new $(PROJECT) -overwrite
set_global_assignment -name FAMILY $(FAMILY)
set_global_assignment -name DEVICE $(DEVICE)
set_global_assignment -name TOP_LEVEL_ENTITY $(TOP)


set_global_assignment -name TIMEQUEST_DO_CCPP_REMOVAL ON

set_global_assignment -name SYNCHRONIZER_IDENTIFICATION AUTO
set_global_assignment -name ALLOW_POWER_UP_DONT_CARE OFF

# set_global_assignment -name ENABLE_INIT_DONE_OUTPUT ON
# set_global_assignment -name ENABLE_OCT_DONE ON
# set_global_assignment -name ENABLE_NCEO_OUTPUT ON
# set_global_assignment -name ENABLE_CONFIGURATION_PINS OFF
# set_global_assignment -name ENABLE_BOOT_SEL_PIN OFF
# set_global_assignment -name USE_CONFIGURATION_DEVICE OFF
# set_global_assignment -name ENABLE_CRC_ERROR_PIN ON
# set_global_assignment -name CRC_ERROR_OPEN_DRAIN ON
# set_global_assignment -name STRATIXV_CONFIGURATION_SCHEME "PASSIVE PARALLEL X16"
set_global_assignment -name ON_CHIP_BITSTREAM_DECOMPRESSION OFF

set_global_assignment -name TIMEQUEST_REPORT_SCRIPT $(HDL_BUILD_PATH)/intel/synth_timequest_rpt_gen.tcl

if { [file exists "$(ABSPATH_QUARTUS_FILE)"] == 1} {
    source $(ABSPATH_QUARTUS_FILE)
}

if { [file exists "$(ABSPATH_XCVR_SETTINGS)"] == 1} {
    source $(ABSPATH_XCVR_SETTINGS)
}

set_global_assignment -name VERILOG_MACRO SYNTHESIS=1
set_global_assignment -name SEED 1

endef


define sdc_tcl
if { [file exists \"$(ABSPATH_SDC_FILE)\"] == 1} {
    set_global_assignment -name SDC_ENTITY_FILE $(ABSPATH_SDC_FILE) -entity $(TOP) -no_sdc_promotion
}
set_global_assignment -name SDC_FILE $(HDL_BUILD_PATH)/intel/jtag.sdc

endef

# Convert the raw string above into `echo -e` friendly strings
synth_global = $(subst ",\", $(subst $(newline),\n,$(global_tcl)))
synth_sdc = $(subst ',\', $(subst $(newline),\n,$(sdc_tcl)))
