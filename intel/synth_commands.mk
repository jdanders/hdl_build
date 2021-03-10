# This is needed for subst command below
define newline


endef

# The "$*" is replaced with the stem, which is the module name
# set $(fpath) to the filename
# set $(ftype) to "$(subst .,,$(suffix $(fpath)))" for filename suffix
# set ipsearch if needed for qsys

# This is the makefile that will be generated to create IP and QSYS files
define ip_makefile_raw
$(IP_DIR)/$*/$*.qip: $(IP_DIR)/$*.$(ftype)
	@-rm -rf $(IP_DIR)/$*/
	@$(BUILD_SCRIPTS)/run_print_err_only.sh \
	   "Generating $(ftype) $* (started $(DATE))" \
	   "$(QGEN_IP) $(ipsearch) $(IPGEN_ARGS)$(IP_DIR)/$*.$(ftype)" \
	   $(BLOG_DIR)/$(ftype)_ipgen_$*.log
	@-cp -a $(IP_DIR)/$*/synthesis/* $(IP_DIR)/$* 2>/dev/null || true

$(DONE_DIR)/qgen_ip.done: $(IP_DIR)/$*/$*.qip

endef

# This is the makefile that will be generated to create Megawizard files
define qmegawiz_makefile_raw
$(IP_DIR)/$*/$*.qip: $(fpath)
	@-rm -rf $(IP_DIR)/$*/
	@mkdir -p $(IP_DIR)/$*
	@cp $(fpath) $(IP_DIR)/$*/$*.v
	@$(BUILD_SCRIPTS)/run_print_err_only.sh \
	   "Generating megawizard $* (started $(DATE))" \
	   "cd $(IP_DIR)/$*/ && $(QMW) -silent $*.v" \
	   $(BLOG_DIR)/$(ftype)_ipgen_$*.log	@c

$(DONE_DIR)/qgen_ip.done: $(IP_DIR)/$*/$*.qip

endef

# Convert the raw string above into `echo -e` friendly strings
ip_makefile = $(subst ",\", $(subst $(newline),\n,$(ip_makefile_raw)))
qmegawiz_makefile = $(subst ",\", $(subst $(newline),\n,$(qmegawiz_makefile_raw)))


# These define the commands to run for quartus .o files
define svh_cmd_raw
echo "set_global_assignment -name SEARCH_PATH $(fdir)" > $(FILES_TCL).$*
endef

define sv_cmd_raw
echo "set_global_assignment -name SOURCE_FILE $(fpath)" > $(FILES_TCL).$*
endef

# Qsys files get copied, maybe updated to Pro, and added to IP_MK qnd QSF file
define qsys_cmd_raw
cp $(fpath) $(IP_DIR)/$*.qsys &&
if [[ "$(PRO_VERSION)" == "pro" ]] &&
      ! grep -q "tool=\"QsysPro\"" $(IP_DIR)/$*.qsys; then
    perl -pi -e "s^\\<component\\n^\\<component\\n   tool=\"QsysPro\"\\n^igs" -0 $(IP_DIR)/$*.qsys
fi &&

echo -e "$(ip_makefile)" > $(IP_MK).$* &&
echo "set_global_assignment -name QIP_FILE $(IP_DIR)/$*/$*.qip" > $(FILES_TCL).$* &&
echo "set_global_assignment -name IP_SEARCH_PATHS $(fdir)" >> $(FILES_TCL).$*

endef


# IP files need to be copied and added to IP_MK and QSF file
define ip_cmd_raw
cp $(fpath) $(IP_DIR)/$*.ip &&
echo -e "$(ip_makefile)" > $(IP_MK).$* &&
echo "set_global_assignment -name QIP_FILE $(IP_DIR)/$*/$*.qip" > $(FILES_TCL).$*

endef


# Megawizard .v files need to be added to IP_MK and QSF file
define qmegawiz_cmd_raw
echo -e "$(qmegawiz_makefile)" > $(IP_MK).$* &&
echo "set_global_assignment -name QIP_FILE $(IP_DIR)/$*/$*.qip" > $(FILES_TCL).$*

endef

# Convert the raw string above into `echo -e` friendly strings
qsys_cmd = $(subst ",", $(subst $(newline),\n,$(qsys_cmd_raw)))
ip_cmd = $(subst ",", $(subst $(newline),\n,$(ip_cmd_raw)))
qmegawiz_cmd = $(subst ",", $(subst $(newline),\n,$(qmegawiz_cmd_raw)))
svh_cmd = $(subst ",", $(subst $(newline),\n,$(svh_cmd_raw)))
sv_cmd = $(subst ",", $(subst $(newline),\n,$(sv_cmd_raw)))
