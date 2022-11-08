#-*- makefile -*-

# This is needed for subst command below
define newline


endef


define path_tcl

set outputDir $(SYNTH_DIR)

endef

PARAM_STRING = 	$(shell cat "$(PARAMETER_TCL)")

# This comes after reading in source files
define synth_tcl

synth_design -top $(TOP_SYNTH) -part $(DEVICE) $(PARAM_STRING) $(SYNTH_SETTINGS)
write_checkpoint -force $(SYNTH_DIR)/post_synth.dcp
report_timing_summary -file $(SYNTH_DIR)/post_synth_timing_summary.rpt
report_utilization -file $(SYNTH_DIR)/post_synth_util.rpt

endef


define impl_tcl

set outputDir $(SYNTH_DIR)

opt_design
place_design
report_clock_utilization -file $(SYNTH_DIR)/clock_util.rpt

# Optionally run optimization if there are timing violations after placement
if {[get_property SLACK [get_timing_paths -max_paths 1 -nworst 1 -setup]] < 0} {
    puts \"Found setup timing violations => running physical optimization\"
    phys_opt_design
}

write_checkpoint -force $(SYNTH_DIR)/post_place.dcp
report_utilization -file $(SYNTH_DIR)/post_place_util.rpt
report_timing_summary -file $(SYNTH_DIR)/post_place_timing_summary.rpt

route_design
write_checkpoint -force $(SYNTH_DIR)/post_route.dcp
report_route_status -file $(SYNTH_DIR)/post_route_status.rpt
report_timing_summary -file $(SYNTH_DIR)/post_route_timing_summary.rpt
report_power -file $(SYNTH_DIR)/post_route_power.rpt
report_drc -file $(SYNTH_DIR)/post_imp_drc.rpt

endef

define bitstream_tcl

set outputDir $(SYNTH_DIR)

write_bitstream -force $(SYNTH_DIR)/$(TOP_SYNTH).bit
write_debug_probes -force $(SYNTH_DIR)/$(TOP_SYNTH).ltx

endef

# Convert the raw string above into `echo -e` friendly strings
synth_path = $(subst ",\", $(subst $(newline),\n,$(path_tcl)))
synth_start = $(subst ",\", $(subst $(newline),\n,$(synth_tcl)))
synth_impl = $(subst ',\', $(subst $(newline),\n,$(impl_tcl)))
synth_bitgen = $(subst ',\', $(subst $(newline),\n,$(bitstream_tcl)))
