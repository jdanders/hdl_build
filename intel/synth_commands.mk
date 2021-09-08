# This is needed for subst command below
define newline


endef

# The "$*" is replaced with the stem, which is the module name
# set $(fpath) to the filename
# set $(ftype) to "$(subst .,,$(suffix $(fpath)))" for filename suffix
# set ipsearch if needed for qsys

# This is the makefile that will be generated to create IP and QSYS files
define ip_makefile_raw
$(IP_DIR)/$${MNAME}/$${MNAME}.qip: $(IP_DIR)/$${MNAME}.$(ftype)
	@-rm -rf $(IP_DIR)/$${MNAME}/
	@$(BUILD_SCRIPTS)/run_print_err_only.sh \
	   "Generating $(ftype) $${MNAME} (started $(DATE))" \
	   "$(QGEN_IP) $(ipsearch) $(IPGEN_ARGS)$(IP_DIR)/$${MNAME}.$(ftype)" \
	   $(BLOG_DIR)/$(ftype)_ipgen_$${MNAME}.log
	@-cp -a $(IP_DIR)/$${MNAME}/synthesis/* $(IP_DIR)/$${MNAME} 2>/dev/null || true

$(DONE_DIR)/qgen_ip.done: $(IP_DIR)/$${MNAME}/$${MNAME}.qip

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
# If directory named 'ip' exists, copy that too for compatibility
define qsys_cmd_raw
cp $(fpath) $(IP_DIR)/$*.qsys
if [[ "$(PRO_VERSION)" == "pro" ]] &&
      ! grep -q "tool=\"QsysPro\"" $(IP_DIR)/$*.qsys; then
    perl -pi -e "s^\\<component\\n^\\<component\\n   tool=\"QsysPro\"\\n^igs" -0 $(IP_DIR)/$*.qsys
fi

# Extra work for multi-IP qsys: copy ip as needed, also add sub ip as deps
F_IP=$$(dirname $(fpath))/ip
if [ -d $${F_IP} ]; then
    cp -a $${F_IP} $(IP_DIR)/
    for IPPATH in $$(find $${F_IP} -name "*.ip"); do
	MNAME=$$(basename $${IPPATH} .ip)
        mkdir -p $(IP_DIR)/ip/$*
        ln -s $(IP_DIR)/$${MNAME} $(IP_DIR)/ip/$*/
	cp $${IPPATH} $(IP_DIR)/
        echo -e "$(ip_makefile)" > $(IP_MK).$${MNAME}
	sed -i "s/\\.qsys/.ip/g" $(IP_MK).$${MNAME}
        echo "set_global_assignment -name QIP_FILE $(IP_DIR)/$${MNAME}/$${MNAME}.qip" > $(FILES_TCL).$${MNAME}
    done
fi

MNAME=$*
echo -e "$(ip_makefile)" > $(IP_MK).$*
echo "set_global_assignment -name QIP_FILE $(IP_DIR)/$*/$*.qip" > $(FILES_TCL).$*
echo "set_global_assignment -name IP_SEARCH_PATHS $(fdir)" >> $(FILES_TCL).$*

endef


# IP files need to be copied and added to IP_MK and QSF file
define ip_cmd_raw
cp $(fpath) $(IP_DIR)/$*.ip
export MNAME=$*
echo -e "$(ip_makefile)" > $(IP_MK).$*
echo "set_global_assignment -name QIP_FILE $(IP_DIR)/$*/$*.qip" > $(FILES_TCL).$*

endef


# Megawizard .v files need to be added to IP_MK and QSF file
define qmegawiz_cmd_raw
echo -e "$(qmegawiz_makefile)" > $(IP_MK).$*
echo "set_global_assignment -name QIP_FILE $(IP_DIR)/$*/$*.qip" > $(FILES_TCL).$*

endef

# Convert the raw string above into `echo -e` friendly strings
qsys_cmd = $(subst ",", $(subst $(newline),\n,$(qsys_cmd_raw)))
ip_cmd = $(subst ",", $(subst $(newline),\n,$(ip_cmd_raw)))
qmegawiz_cmd = $(subst ",", $(subst $(newline),\n,$(qmegawiz_cmd_raw)))
svh_cmd = $(subst ",", $(subst $(newline),\n,$(svh_cmd_raw)))
sv_cmd = $(subst ",", $(subst $(newline),\n,$(sv_cmd_raw)))
