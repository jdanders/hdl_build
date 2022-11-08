# This is needed for subst command below
define newline


endef

# The "$*" is replaced with the stem, which is the module name
# set $(fpath) to the filename
# set $(ftype) to "$(subst .,,$(suffix $(fpath)))" for filename suffix


# This is the makefile that will be generated to create ip files
define ip_makefile_raw
$(IP_DIR)/$${MNAME}/$${MNAME}.done: $(IP_DIR)/$${MNAME}.$(ftype) $(IP_DIR)/$${MNAME}_gen.tcl
	@-rm -rf $(IP_DIR)/$${MNAME}/
	@$(BUILD_SCRIPTS)/run_print_err_only.sh \
	   "Generating $(ftype) $${MNAME} (started $(DATE)) see $(BLOG_DIR)/$(ftype)_ipgen_$${MNAME}.log" \
	   "$(VIVADO_BATCH) -source $(IP_DIR)/$${MNAME}_gen.tcl " \
	   $(BLOG_DIR)/$(ftype)_ipgen_$${MNAME}.log
	@touch $(IP_DIR)/$${MNAME}/$${MNAME}.done

$(IP_DIR)/$${MNAME}_gen.tcl:
	@echo "create_project -in_memory -part $(DEVICE) -force $${MNAME}_project" > $(IP_DIR)/$${MNAME}_gen.tcl
	@echo "read_ip $(IP_DIR)/$${MNAME}.xci" >> $(IP_DIR)/$${MNAME}_gen.tcl
	@echo "generate_target all [get_files $${MNAME}.xci]" >> $(IP_DIR)/$${MNAME}_gen.tcl
	@echo "synth_ip [get_files $${MNAME}.xci]" >> $(IP_DIR)/$${MNAME}_gen.tcl
	@echo "upgrade_ip [get_ips {$${MNAME}}]" >> $(IP_DIR)/$${MNAME}_gen.tcl
	@touch $@

$(DONE_DIR)/gen_ip.done: $(IP_DIR)/$${MNAME}/$${MNAME}.done

endef

ip_makefile = $(subst ",\", $(subst $(newline),\n,$(ip_makefile_raw)))

# These define the commands to run for vivado .o files
define sv_cmd_raw
echo "read_verilog $(fpath)" > $(FILES_TCL).$*
endef



# XCI files get copied and added to IP_MK file
define xci_cmd_raw
python3 $(HDL_BUILD_PATH)/xilinx/move_xci.py $(fpath) $(IP_DIR)/$*.xci $*

export MNAME=$*;
echo -e "$(ip_makefile)" > $(IP_MK).$*
echo "read_ip $(IP_DIR)/$*.xci" > $(FILES_TCL).$*

endef


define xcix_cmd_raw

echo "read_ip $(IP_DIR)/$*.xcix" > $(FILES_TCL).$*

endef


# Convert the raw strings above into `echo -e` friendly strings
sv_cmd = $(subst ",", $(subst $(newline),\n,$(sv_cmd_raw)))
xci_cmd = $(subst ",", $(subst $(newline),\n,$(xci_cmd_raw)))
xcix_cmd = $(subst ",", $(subst $(newline),\n,$(xcix_cmd_raw)))
