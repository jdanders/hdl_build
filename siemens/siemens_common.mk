#-*- makefile -*-

# Use this rule in a Makefile to force a recipe to execute before libraries
presimlib_hook := $(DONE_DIR)/presimlib_hook.done
## target hook to run before sim libraries
$(presimlib_hook): | $(DONE_DIR)
	@touch $@

# Use this rule in a Makefile to force a recipe to execute before comp
precomp_hook := $(DONE_DIR)/precomp_hook.done
## target hook to run before compilation
$(precomp_hook): | $(DONE_DIR)
	@touch $@

# Use this rule in a Makefile to force a recipe to execute before simulation
presim_hook := $(DONE_DIR)/presim_hook.done
## target hook to run before starting sim
$(presim_hook): | $(DONE_DIR)
	@touch $@


##################### Simulation Parameters ##############################

TRANSCRIPT := $(BLD_DIR)/transcript
WORK := $(SIM_LIB_DIR)/work
SIM_SCRIPT := $(BLD_DIR)/sim.do
BATCH_SCRIPT := $(BLD_DIR)/batch.do
## `bld/restart.do` can be used in the simulator to recompile source and restart the simulation using `restart -f`. The current session and waveform is backed up first. The first optional parameter is `log` which will log all signals and memories after restart. Following parameters will be executed after restart. For example: `do bld/restart.do log run 100 ns` will log things and then run for 100 ns. It can be helpful to tie the command to a keyboard shortcut.
RESTART_SCRIPT := $(BLD_DIR)/restart.do
## `bld/resim.do` can be used in the simulator to recompile source and restart the simulation using `quit -sim`. The current session and waveform is backed up first and the transcript is archived and cleared. The first optional parameter is `log` which will log all signals and memories after restart. Following parameters will be executed after restart. For example: `do bld/resim.do log run 100 ns` will log things and then run for 100 ns. It can be helpful to tie the command to a keyboard shortcut.
RESIM_SCRIPT := $(BLD_DIR)/resim.do
ifndef SIM_SEED
  SIM_SEED := 9149
endif

$(SIM_LIB_DIR):
	@mkdir -p $(SIM_LIB_DIR)

##### Upper Makefile simulation settings ####
## extra options for `vlog` command
# VLOG_OPTIONS : set in upper Makefile
## extra options for `vopt` command
# VOPT_OPTIONS : set in upper Makefile
## extra options for `vsim` command
# VSIM_OPTIONS : set in upper Makefile


# In order to more closely simulate hardware conditions, default all registers to '0' instead of 'X'
# See Quartus Handbook, "Specifying a Power-Up Value" where it says
# "Registers power up to 0 by default" unless NOT gate push-back is specified.
# Also default all "memories" to zero (which includes any unpacked vectors or
#   structs).
# Also promote warning 2182 to error, which says "'signal_name' might be read
#   before written in always_comb or always @* block".
# Disable warnings about "Too few port connections" and "Some checking for
#   conflicts with always_comb and always_latch variables not yet supported."
VLOG_PARAMS := $(VLOG_OPTIONS) $(VLOG_INCLUDES) $(MS_INI_PARAM) +initreg+0 +initmem+0 -error 2182 +nowarnSVCHK $(MSIM_VOPT)

WLF_PARAM := -wlf $(BLD_DIR)/vsim.wlf

VSIM_PARAMS := -msgmode both -t 1ps -permit_unmatched_virtual_intf $(MSIM_VSIM) $(SUPPRESS_PARAMS) $(WLF_PARAM) $(MS_INI_PARAM) $(VSIM_OPTIONS) $(VSIM_LDFLAGS)

SIM_LAST_DEPS := $(SIM_LIB_DIR)/sim_top_deps

# The onfinish stop makes sure we can execute commands after run -all
# before the simulator exits.  Without that, if someone used a $finish
# at the end of their simulation the simulator would exit right after
# run -all and skip any commands that come after that.
BATCH_OPTIONS := -batch -do "onfinish stop; run -all; exit"
# Elaboration should just quit as soon as it starts
ELAB_OPTIONS := -batch -do "exit"

# Compare against old results, and force update if different
ifeq ($(shell $(BUILD_SCRIPTS)/variable_change.sh "$(SIM_PARAM)" $(PARAMETER_DONE)),yes)
SIM_PARAM_DEP=$(PARAMETER_DONE).tmp
endif

##### Parameters ##
## monitors variables prefixed with **`PARAM_`** and passes them to simulator. `PARAM_NUM_PACKETS := 20` passes a parameter named NUM_PACKETS with value of 20.
# PARAM_*: set in upper Makefile

# Update the parameters if any of the PARAM_ variable change
$(PARAMETER_DONE).tmp: | $(DONE_DIR)
	@echo "$(SIM_PARAM)" > $@
	@if [ ! -f $(PARAMETER_DONE) ]; then echo; echo "Recording PARAM_ parameters" && cp $@ $(PARAMETER_DONE); fi
$(PARAMETER_DONE): $(SIM_PARAM_DEP)
	@-diff $@.tmp $@ >/dev/null 2>&1 \
	    && rm $@.tmp \
	    || (echo "Updating PARAM_ parameters" && mv $@.tmp $@);
	@touch $@


$(MS_INI): $(SRC_MAKEFILES) | $(BLD_DIR) $(SIM_LIB_DIR)
	@echo;echo -e "$O Creating sim environment $C"
	@if which vmap &> /dev/null; then vmap -c > /dev/null; mv modelsim.ini $(MS_INI);\
	 else echo -e "$(RED)Could not find vmap on current path$(NC)"; false; \
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
# to run make commands cleanly in GUI, remove -j flags
## target to run simulation in GUI
sim: $(PARAMETER_DONE) $(PRESIM_GOAL) $(presim_hook)
	@echo -e "$(sim_do_str)" > $(SIM_SCRIPT)
	@echo -e '$(restart_str)' > $(RESTART_SCRIPT)
	@echo -e '$(resim_str)' > $(RESIM_SCRIPT)
	@echo -e "$O Starting simulation $C"
	MAKEFLAGS="-r" vsim $(MS_INI_PARAM) -i -do $(SIM_SCRIPT)&


.PHONY: elab_sim
## target to run elaboration batch
elab_sim: $(PARAMETER_DONE) $(PRESIM_GOAL) $(presim_hook)
	@echo -e "$(elab_str)" > $(BATCH_SCRIPT)
	@chmod +x $(BATCH_SCRIPT)
	@echo -e "$O Starting batch simulation $C (see $(BLOG_DIR)/batch.log)"
	@$(HDL_BUILD_PATH)/siemens/run_siemens.sh "./$(BATCH_SCRIPT)" \
	 "./$(BATCH_SCRIPT)" "$(BLOG_DIR)/batch.log"


.PHONY: batch
## target to run simulation batch
batch: $(PARAMETER_DONE) $(PRESIM_GOAL) $(presim_hook)
	@echo -e "$(batch_str)" > $(BATCH_SCRIPT)
	@chmod +x $(BATCH_SCRIPT)
	@echo -e "$O Starting batch simulation $C (see $(BLOG_DIR)/batch.log)"
	@if $(HDL_BUILD_PATH)/siemens/run_siemens.sh "./$(BATCH_SCRIPT)" \
	    "./$(BATCH_SCRIPT)" "$(BLOG_DIR)/batch.log" ; then \
	     echo -e "$(GREEN)# Simulation successful $C"; \
	 else false; fi;

.PHONY: autocheck_batch
## (or `ac_batch`) Run autocheck in console only
autocheck_batch: $(AC_DONE)
	@$(HDL_BUILD_PATH)/siemens/ac_pretty.sh '$(AC_REPORT)';
.PHONY: ac_batch
ac_batch: autocheck_batch

.PHONY: autocheck
## (or `ac`) Run autocheck GUI
autocheck: $(AC_DONE)
	@-$(HDL_BUILD_PATH)/siemens/ac_pretty.sh '$(AC_REPORT)';
	@echo -e "$O Starting autocheck GUI $C"
	@cd $(AC_OUT_DIR) && qverify autocheck_verify.db &
.PHONY: ac
ac: autocheck

.PHONY: clean
clean: clean_siemens
.PHONY: clean_siemens
clean_siemens:
	@rm -rf $(SIM_SCRIPT) $(BATCH_SCRIPT) $(RESTART_SCRIPT) $(RESIM_SCRIPT) $(SIM_LIB_DIR) $(WORK) certe_dump.xml
	@if [[ "$(MAKECMDGOALS)" == *comp* ]]; then make --no-print-directory -r $(DEP_DIR)/$(SIEMENS_TOP).d; fi

.PHONY: cleanall
cleanall: cleanall_siemens
.PHONY: cleanall_siemens
cleanall_siemens:
#	@rm -rf $(ALTERA_SIM_LIBS)
	@rm -f $(MS_INI) transcript autobackup*.do vsim_stacktrace.vstf
