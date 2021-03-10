#-*- makefile -*-

# Use this rule in a Makefile to force a recipe to execute before libraries
presimlib_hook := $(DONE_DIR)/presimlib_hook.done
$(presimlib_hook): | $(DONE_DIR) ## hook to run before sim libraries
	@touch $@

# Use this rule in a Makefile to force a recipe to execute before comp
precomp_hook := $(DONE_DIR)/precomp_hook.done
$(precomp_hook): | $(DONE_DIR) ## hook to run before compilation
	@touch $@

# Use this rule in a Makefile to force a recipe to execute before simulation
presim_hook := $(DONE_DIR)/presim_hook.done
$(presim_hook): | $(DONE_DIR) ## hook to run before starting sim
	@touch $@


##################### Simulation Parameters ##############################

TRANSCRIPT := $(BLD_DIR)/transcript
WORK := $(SIM_LIB_DIR)/work
PARAMETER_DONE := $(DONE_DIR)/parameters.done
RUN_SCRIPT := $(BLD_DIR)/run.do
BATCH_SCRIPT := $(BLD_DIR)/batch.do
REDO_SCRIPT := $(BLD_DIR)/redo.do
ifndef SIM_SEED
  SIM_SEED := 9149
endif

$(SIM_LIB_DIR):
	@mkdir -p $(SIM_LIB_DIR)

# In order to more closely simulate hardware conditions, default all registers to '0' instead of 'X'
# See Quartus Handbook, "Specifying a Power-Up Value" where it says
# "Registers power up to 0 by default" unless NOT gate push-back is specified.
# Also default all "memories" to zero (which includes any unpacked vectors or
#   structs).
# Also promote warning 2182 to error, which says "'signal_name' might be read
#   before written in always_comb or always @* block".
# Disable warnings about "Too few port connections" and "Some checking for
#   conflicts with always_comb and always_latch variables not yet supported."
VLOG_PARAMS := $(VLOG_OPTIONS) $(MS_INI_PARAM) +initreg+0 +initmem+0 -error 2182 +nowarnSVCHK $(UVM_DPILIB_VLOG_OPT) $(VLOG_COVER_OPT) $(MSIM_VOPT)

WLF_PARAM := -wlf $(BLD_DIR)/vsim.wlf
# set VSIM_COVER_OPT=-coverage to run a coverage test (or use smake)
VSIM_PARAMS := -msgmode both -t 1ps -permit_unmatched_virtual_intf $(SUPRESS_PARAMS) $(WLF_PARAM) $(MS_INI_PARAM) $(VSIM_COVER_OPT) $(VSIM_OPTIONS) $(VSIM_LDFLAGS)

SIM_LAST_DEPS := $(SIM_LIB_DIR)/sim_top_deps

# The onfinish stop makes sure we can execute commands after run -all
# before the simulator exits.  Without that, if someone used a $finish
# at the end of their simulation the simulator would exit right after
# run -all and skip any commands that come after that.
BATCH_OPTIONS := -batch -do "onfinish stop; run -all; $(COV_COMMANDS); exit"
# Elaboration should just quit as soon as it starts
ELAB_OPTIONS := -batch -do "exit"

# Compare against old results, and force update if different
ifeq ($(shell $(BUILD_SCRIPTS)/variable_change.sh "$(SIM_PARAM)" $(PARAMETER_DONE)),yes)
SIM_PARAM_DEP=$(PARAMETER_DONE).tmp
endif

# Update the parameters if any of the PARAM_ variable change
$(PARAMETER_DONE).tmp: | $(DONE_DIR)
	@echo "$(SIM_PARAM)" > $@
	@if [ ! -f $(PARAMETER_DONE) ]; then echo; echo "Recording PARAM_ parameters" && cp $@ $(PARAMETER_DONE); fi
$(PARAMETER_DONE): $(SIM_PARAM_DEP)
	@-diff $@.tmp $@ >/dev/null 2>&1 \
	    && rm $@.tmp \
	    || (echo "Updating PARAM_ parameters" && mv $@.tmp $@);
	@touch $@


TOOL_MODELSIM.INI := $(abspath $(shell which vsim || echo /dev/null)/../../modelsim.ini)
$(MS_INI): $(SRC_MAKEFILES) | $(BLD_DIR) $(SIM_LIB_DIR)
	@echo;echo -e "$O Creating sim environment $C"
	@if [ -f $(TOOL_MODELSIM.INI) ]; then \
	  cp $(TOOL_MODELSIM.INI) $(MS_INI); \
	else echo -e "$(RED)Could not find installed modelsim.ini$(NC)"; false; \
	fi
	@chmod +w $(MS_INI)
	@rm -rf $(WORK) && vlib $(WORK)
	@echo "work = $(WORK)" > $(SIM_LIB_DIR)/work.map;
	@sed -i 's|TranscriptFile = transcript|TranscriptFile = $(TRANSCRIPT)|g' $(MS_INI)
	@touch $@

# Maintain the sim libraries: create and map in $(MS_INI) in parallel safe way
# Watch for changes in dependenies and force update upon change
ifeq ($(shell $(BUILD_SCRIPTS)/variable_change.sh "$(SIM_TOP_DEPS)" $(SIM_LAST_DEPS)),yes)
NEW_SIM_DEPS=$(SIM_LAST_DEPS).tmp
endif
$(SIM_LAST_DEPS).tmp: | $(SIM_LIB_DIR)
	@echo "$(SIM_TOP_DEPS)" > $@
$(SIM_LAST_DEPS): $(NEW_SIM_DEPS)
	@-diff $@.tmp $@ >/dev/null 2>&1 \
	    && rm $@.tmp \
	    || (echo "Simulation dependencies changed" && mv $@.tmp $@);
	@touch $@

# Create vlib and a map file for each dependency
$(SIM_LIB_DIR)/maps_made: $(presimlib_hook) $(SIM_LAST_DEPS) | $(SIM_LIB_DIR)
	@echo "Updating sim lib map list"
	@for ii in $(SIM_TOP_DEPS); do if [ ! -f  $(SIM_LIB_DIR)/$${ii}.seen ]; then \
	    touch $(SIM_LIB_DIR)/$${ii}.seen; \
	    if [ ! -d $(SIM_LIB_DIR)/$${ii} ] ; then vlib $(SIM_LIB_DIR)/$${ii}; fi ; \
	    echo "$${ii} = $(SIM_LIB_DIR)/$${ii}" > $(SIM_LIB_DIR)/$${ii}.map; \
        fi& done; wait #Run all the loops in the background and wait
	@touch $@

# Each sim library needs a mapping. Do modification of $(MS_INI) in one step
# If diff, grep remove old mappings and sed insert $@ into $(MS_INI) at [Library]
$(SIM_LIB_DONE): $(MS_INI) $(SIM_LIB_DIR)/maps_made | $(SIM_LIB_DIR)
	@echo "Checking for new sim libraries"
	@grep "$(SIM_LIB_DIR)" $(MS_INI) > $@ || touch $@
	@cat $(SIM_LIB_DIR)/*.map > $@.new
	@if [ ! -f $@ ]; then \
	  echo  -e "$O Creating library mappings $C"; \
	  mv $@.new $@; \
	  sed -i '/\[Library\]/r./$@' $(MS_INI); \
	else \
	  if ! diff $@ $@.new > /dev/null; then \
	    echo  -e "$O Updating library mappings $C"; \
	    mv $@.new $@; \
	    grep -v $(SIM_LIB_DIR) $(MS_INI) > $(MS_INI).tmp; \
	    mv $(MS_INI).tmp $(MS_INI); \
	    sed -i '/\[Library\]/r./$@' $(MS_INI); \
	  else \
	    rm $@.new; \
	  fi; \
	fi
	@touch $@


# Build dependencies for SIM_SUBSTITUTIONS variable
# Compare against old results, and force update if different
ifeq ($(shell $(BUILD_SCRIPTS)/variable_change.sh "$(SIM_SUBSTITUTIONS)" $(SIM_SUB_DONE)),yes)
SIMSUB_DEP=$(SIM_SUB_DONE).tmp
endif

# Update the substitutions if the SIM_SUBSTITUTIONS variable changes
$(SIM_SUB_DONE).tmp: | $(DONE_DIR)
	@echo "$(SIM_SUBSTITUTIONS)" > $@
	@if [ ! -f $(SIM_SUB_DONE) ]; then echo "Recording SIM_SUBSTITUTIONS" && cp $@ $(SIM_SUB_DONE); fi
$(SIM_SUB_DONE): $(SIMSUB_DEP)
	@-diff $@.tmp $@ >/dev/null 2>&1 \
	    && rm $@.tmp \
	    || (echo "Updating SIM_SUBSTITUTIONS" && mv $@.tmp $@);
	@touch $@


##################### Do script targets ##############################
include $(HDL_BUILD_PATH)/siemens/do_files.mk
.PHONY: sim
sim: $(PRESIM_GOAL) $(presim_hook) ## Run simulation in GUI
	@echo -e "$(run_str)" > $(RUN_SCRIPT)
	@echo -e '$(redo_str)' > $(REDO_SCRIPT)
	@echo -e "$O Starting simulation $C"
	MAKEFLAGS="-$(filter-out --jobserver-fds=%,$(MAKEFLAGS))" vsim $(MS_INI_PARAM) -i -do $(RUN_SCRIPT)&


.PHONY: elab_sim
elab_sim: $(PRESIM_GOAL) $(presim_hook) ## Run elaboration batch
	@echo -e "$(elab_str)" > $(BATCH_SCRIPT)
	@chmod +x $(BATCH_SCRIPT)
	@echo -e "$O Starting batch simulation $C (see $(BLOG_DIR)/batch.log)"
	@$(BUILD_SCRIPTS)/run_full_log_on_err.sh "./$(BATCH_SCRIPT)" \
	 "./$(BATCH_SCRIPT)" "$(BLOG_DIR)/batch.log"


.PHONY: batch
batch: $(PRESIM_GOAL) $(presim_hook) ## Run simulation batch
	@echo -e "$(batch_str)" > $(BATCH_SCRIPT)
	@chmod +x $(BATCH_SCRIPT)
	@echo -e "$O Starting batch simulation $C (see $(BLOG_DIR)/batch.log)"
	@if $(BUILD_SCRIPTS)/run_full_log_on_err.sh "./$(BATCH_SCRIPT)" \
	    "./$(BATCH_SCRIPT)" "$(BLOG_DIR)/batch.log" ; then \
	     echo -e "$(GREEN)# Simulation successful $C"; \
	 fi;


.PHONY: clean
clean: clean_siemens
.PHONY: clean_siemens
clean_siemens:
	@rm -rf $(RUN_SCRIPT) $(BATCH_SCRIPT) $(REDO_SCRIPT) $(SIM_LIB_DIR) $(WORK) certe_dump.xml
	@if [[ "$(MAKECMDGOALS)" == *comp* ]]; then make --no-print-directory -r $(DEP_DIR)/$(TOP_TB).d; fi

.PHONY: cleanall
cleanall: cleanall_siemens
.PHONY: cleanall_siemens
cleanall_siemens:
#	@rm -rf $(ALTERA_SIM_LIBS)
	@rm -f $(MS_INI) transcript autobackup*.do vsim_stacktrace.vstf
