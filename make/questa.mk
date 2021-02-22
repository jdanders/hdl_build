#-*- makefile -*-
#--- Questa build rules: ## ----------------
DEFAULT_SIM_TOOL := questa_10.7
ifndef SIM_TOOL
  SIM_TOOL := $(DEFAULT_SIM_TOOL)
endif

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

SIM_SUB_DONE := $(DONE_DIR)/sim_substitutions.done

include $(BUILD_PATH)/make/color.mk

# To print variables that need full dependency includes
# for example: make printquesta-SIM_LIB_LIST
.PHONY: printquesta-%
printquesta-%: ## use 'make printquesta-VAR_NAME' to print variable after questa processing
	@echo '$* = $($*)'


##################### Module dependency targets ##############################

MAKEDEP_TOOL_QUESTA := "questa"
SUBS_QUESTA := --subsfilelist '$(SIM_SUBSTITUTIONS)'

# The .d (dependent) targets are to calculate the dependencies of a file
# The .d recipe is run whenever the sv file changes
# The sv dependency is added in the .d file itself
# The '%' becomes the module name
# The '$*' is replaced by that module name
$(DEP_DIR)/%.questa.d: $(SIM_SUB_DONE) $(predependency_hook) | $(DEP_DIR) $(BLOG_DIR)
	@if [ -d "$(SRC_BASE_DIR)" ]; then\
	  $(SCRIPTS)/run_full_log_on_err.sh  \
	   "$(CLEAR)Identifying dependencies for $*$(UPDATE)" \
	   "$(MAKEDEPEND_CMD) $(SUBS_QUESTA) $(MAKEDEP_TOOL_QUESTA) $*" \
	   $(BLOG_DIR)/dependency_$*_questa.log; \
	else \
	  echo -e "$(RED)Could not find SRC_BASE_DIR$(NC)"; false; \
	fi


##################### Include top level ##############################

# targets: grep lines that have ':', remove cleans, sed drop last character
# Extract all targets for sim:
QUESTA_TARGETS := $(shell grep -oe "^[a-z].*:" $(BUILD_PATH)/make/questa.mk | grep -v clean | grep -v nuke | sed 's/:.*//')

# When the top .d file is included, make can't do anything until built.
# Make sure it's included only when needed to avoid doing extra work
SIM_DEPS := $(filter $(QUESTA_TARGETS),$(MAKECMDGOALS))
ifneq (,$(SIM_DEPS))
  # The top .d file must be called out specifically to get the ball rolling
  # Otherwise nothing happens because there are no matches to the wildcard rule
  ifndef TOP_TB
    $(error No TOP_TB module defined)
  endif
  ifdef	TOP_TB
    -include $(DEP_DIR)/$(TOP_TB).questa.d
  endif
endif


##################### Simulation Parameters ##############################

MS_INI := $(BLD_DIR)/modelsim.ini
TRANSCRIPT := $(BLD_DIR)/transcript
SIM_LIB_DIR := $(BLD_DIR)/simlib
WORK := $(SIM_LIB_DIR)/work
PARAMETER_DONE := $(DONE_DIR)/parameters.done
VOPT_DONE := $(DONE_DIR)/vopt.done
SIM_SEED := 13541
RUN_SCRIPT := $(BLD_DIR)/run.do
BATCH_SCRIPT := $(BLD_DIR)/batch.do
REDO_SCRIPT := $(BLD_DIR)/redo.do

$(SIM_LIB_DIR):
	@mkdir -p $(SIM_LIB_DIR)


# Python cosim
CONFIG_UTIL := python3-config
DPI_OPTIONS := $(shell $(CONFIG_UTIL) --cflags)
# Python 3.8 made getting ldflags complicated
# https://docs.python.org/3/whatsnew/3.8.html#debug-build-uses-the-same-abi-as-release-build
# Pre 3.8 python returned the `lpython` flag without --embed
LD_TEST := $(shell $(CONFIG_UTIL) --ldflags)
ifeq ($(findstring lpython,$(LD_TEST)),lpython)
  VSIM_LDFLAGS := -ldflags "$(LD_TEST)"
else
  VSIM_LDFLAGS := -ldflags "$(shell $(CONFIG_UTIL) --ldflags --embed)"
endif

MS_INI_PARAM := -modelsimini $(MS_INI)

# In order to more closely simulate hardware conditions, default all registers to '0' instead of 'X'
# See Quartus Handbook, "Specifying a Power-Up Value" where it says
# "Registers power up to 0 by default" unless NOT gate push-back is specified.
# Also default all "memories" to zero (which includes any unpacked vectors or
#   structs).
# Also promote warning 2182 to error, which says "'signal_name' might be read
#   before written in always_comb or always @* block".
# Disable warnings about "Too few port connections" and "Some checking for
#   conflicts with always_comb and always_latch variables not yet supported."
VLOG_PARAMS := $(VLOG_OPTIONS) $(MS_INI_PARAM) +initreg+0 +initmem+0 -error 2182 +nowarnSVCHK $(UVM_DPILIB_VLOG_OPT) $(VLOG_COVER_OPT) +define+WIRE= +define+USE_GREG_BFM=1 +define+BLD_DIR=$(BLD_DIR)

SUPRESS_PARAMS := +nowarnTFMPC

VOPT_PARAMS := $(SUPRESS_PARAMS) $(MS_INI_PARAM) $(strip +acc $(VOPT_OPTIONS))

WLF_PARAM := -wlf $(BLD_DIR)/vsim.wlf
# set VSIM_COVER_OPT=-coverage to run a coverage test (or use smake)
VSIM_PARAMS := -msgmode both -t 1ps -permit_unmatched_virtual_intf $(SUPRESS_PARAMS) $(WLF_PARAM) $(MS_INI_PARAM) $(VSIM_COVER_OPT) $(VSIM_OPTIONS) $(VSIM_LDFLAGS)

# This part should match built-in uvm compile to avoid Warning: (vopt-10017)
# -L mtiAvm -L mtiRnm -L mtiOvm -L mtiUvm -L mtiUPF -L infact
DEFAULT_SIM_LIB := -L floatfixlib -L ieee -L ieee_env -L mc2_lib -L mgc_ams -L modelsim_lib -L mtiAvm -L mtiRnm -L mtiOvm -L mtiUvm -L mtiUPF -L infact -L mtiPA -L osvvm -L std -L std_developerskit -L sv_std -L synopsys -L verilog -L vh_ux01v_lib -L vhdlopt_lib -L vital2000

# Create list of libraries to use for vlog and vsim
# In order to build in parallel, each module is in a separate lib
# Use _DEPS variable and replace ' ' with ' -L ', like: -L mod1 -L mod2
SIM_TOP_DEPS := $(sort $(strip $($(TOP_TB)_DEPS)))
SIM_LIB_LIST := $(shell echo " $(SIM_TOP_DEPS)" | sed -E 's| +(\w)| -L \1|g') -L work $(SIM_LIB_APPEND)
SIM_LAST_DEPS := $(SIM_LIB_DIR)/sim_top_deps
SIM_LIB_DONE := $(DONE_DIR)/sim_lib_map

# The onfinish stop makes sure we can execute commands after run -all
# before the simulator exits.  Without that, if someone used a $finish
# at the end of their simulation the simulator would exit right after
# run -all and skip any commands that come after that.
BATCH_OPTIONS := -batch -do "onfinish stop; run -all; $(COV_COMMANDS); exit"
# Elaboration should just quit as soon as it starts
ELAB_OPTIONS := -batch -do "exit"

# Gather all PARAM_ environment variables and make a parameter string
# First filter all variables to find all that start with PARAM_
MAKE_PARAMS := $(filter PARAM_%,$(.VARIABLES))
# Next change them from PARAM_NAME to NAME and grab their values
# This takes PARAM_NAME=value and changes it to -GNAME=value
SIM_PARAM := $(foreach pname, $(MAKE_PARAMS),-G$(subst PARAM_,,$(pname))=$($(pname)))

# Compare against old results, and force update if different
ifeq ($(shell $(SCRIPTS)/variable_change.sh "$(SIM_PARAM)" $(PARAMETER_DONE)),yes)
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


TOOL_MODELSIM.INI := $(abspath $(shell which vsim)/../../modelsim.ini)
$(MS_INI): $(SRC_MAKEFILES) | $(BLD_DIR) $(SIM_LIB_DIR)
	@echo;echo -e "$O Creating sim environment $C"
	@if [ -f $(TOOL_MODELSIM.INI) ]; then \
	  cp $(TOOL_MODELSIM.INI) $(MS_INI); \
	else echo -e "$(RED)Could not find Questa install modelsim.ini$(NC)"; false; \
	fi
	@chmod +w $(MS_INI)
	@rm -rf $(WORK) && vlib $(WORK)
	@echo "work = $(WORK)" > $(SIM_LIB_DIR)/work.map;
	@sed -i 's|TranscriptFile = transcript|TranscriptFile = $(TRANSCRIPT)|g' $(MS_INI)
	@touch $@

# Maintain the sim libraries: create and map in $(MS_INI) in parallel safe way
# Watch for changes in dependenies and force update upon change
ifeq ($(shell $(SCRIPTS)/variable_change.sh "$(SIM_TOP_DEPS)" $(SIM_LAST_DEPS)),yes)
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
ifeq ($(shell $(SCRIPTS)/variable_change.sh "$(SIM_SUBSTITUTIONS)" $(SIM_SUB_DONE)),yes)
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


##################### Dependency targets ##############################
# Create rules to determine dependencies and create compile recipes for .sv
.PHONY: deps
deps: $(DEP_DIR)/$(TOP_TB).questa.d ## Figure out sim dependencies only
.PHONY: comp
comp: $(MS_INI) $(DEP_DIR)/$(TOP_TB).questa.o $(precomp_hook) ## Compile simulation files
.PHONY: vopt
vopt: comp $(VOPT_DONE) ## Perform vopt after compile
.PHONY: filelist_sim
filelist_sim: $(DEP_DIR)/$(TOP_TB).questa.d ## print list of files used in sim
	@grep "\.d:" $(DEP_DIR)/* | cut -d " " -f 2 | sort | uniq
.PHONY: modules_sim
modules_sim: $(DEP_DIR)/$(TOP_TB).questa.d ## print list of modules used in sim
	@echo $(SIM_TOP_DEPS)

# TODO: On some simulations, vopt fails the first time. FIXME!
# for example: cedarbreaks/tie_fpga/tie_system_sim/build_bad_ip_frag
VOPT_CMD := "vopt -sv -work $(SIM_LIB_DIR)/$(TOP_TB) $(VOPT_PARAMS) $(DEFAULT_SIM_LIB) $(SIM_LIB_LIST) $(SIM_PARAM) $(SIM_LIB_DIR)/$(TOP_TB).$(TOP_TB) -o $(TOP_TB)_opt"
VOPT_MSG := "$O Optimizing design $C (see $(BLOG_DIR)/vopt.log)"

$(VOPT_DONE): $(DEP_DIR)/$(TOP_TB).questa.o $(PARAMETER_DONE) | $(DONE_DIR)
	@$(SCRIPTS)/run_print_warn_and_err.sh $(VOPT_MSG) $(VOPT_CMD) $(BLOG_DIR)/vopt.log \
	 || (echo -e "$O Only a problem if second vopt attempt fails... $C" && $(SCRIPTS)/run_print_warn_and_err.sh  $(VOPT_MSG) $(VOPT_CMD) $(BLOG_DIR)/vopt.log)
	@touch $(VOPT_DONE)


# The .o (out) rules are to mark that the file has been compiled
# The .o recipe is used to compile all files
# The source file dependency is added in the .d file
# The "$*" is replaced with the stem, which is the module name
# The "$(word 2,$^)" is the second dependency, which will be the sv filename
# Every '.o' tool rule set needs to be added to build.mk
$(DEP_DIR)/%.questa.o: $(SIM_LIB_DONE) | $(DEP_DIR) $(BLOG_DIR)
	@if [ ! -f $(DEP_DIR)/$*.questa.d ]; then echo -e "$(RED)Dependency .d file missing for $*$(NC)"; exit 1; fi
	@$(SCRIPTS)/run_questa.sh $* $(word 2,$^) $(BLOG_DIR)
	@touch $@


##################### Do script targets ##############################
include $(BUILD_PATH)/make/do_files.mk
.PHONY: sim
sim: vopt $(presim_hook) ## Run simulation in GUI
	@printf "$(run_str)" > $(RUN_SCRIPT)
	@printf '$(redo_str)' > $(REDO_SCRIPT)
	@echo -e "$O Starting simulation $C"
	vsim $(MS_INI_PARAM) -i -do $(RUN_SCRIPT)&


.PHONY: elab_sim
elab_sim: vopt $(presim_hook) ## Run elaboration batch
	@printf "$(elab_str)" > $(BATCH_SCRIPT)
	@chmod +x $(BATCH_SCRIPT)
	@echo -e "$O Starting batch simulation $C (see $(BLOG_DIR)/batch.log)"
	@$(SCRIPTS)/run_full_log_on_err.sh "./$(BATCH_SCRIPT)" \
	 "./$(BATCH_SCRIPT)" "$(BLOG_DIR)/batch.log"


.PHONY: batch
batch: vopt $(presim_hook) ## Run simulation batch
	@printf "$(batch_str)" > $(BATCH_SCRIPT)
	@chmod +x $(BATCH_SCRIPT)
	@echo -e "$O Starting batch simulation $C (see $(BLOG_DIR)/batch.log)"
	@if $(SCRIPTS)/run_full_log_on_err.sh "./$(BATCH_SCRIPT)" \
	    "./$(BATCH_SCRIPT)" "$(BLOG_DIR)/batch.log" ; then \
	   if grep "+-+- Sim Finished -+-+" $(BLOG_DIR)/batch.log > /dev/null; then \
	     echo -e "$(GREEN)# Simulation successful $C"; \
	   else\
	     echo -e "$(RED)# Missing 'Sim Finished' string$C  (see $(BLOG_DIR)/batch.log)"; false;\
	   fi; else false; fi;


.PHONY: clean
clean: clean_questa
.PHONY: clean_questa
clean_questa:
	@rm -rf $(RUN_SCRIPT) $(BATCH_SCRIPT) $(REDO_SCRIPT) $(SIM_LIB_DIR) $(WORK) certe_dump.xml
	@if [[ "$(MAKECMDGOALS)" == *comp* ]]; then make --no-print-directory -r $(DEP_DIR)/$(TOP_TB).d; fi

.PHONY: cleanall
cleanall: cleanall_questa
.PHONY: cleanall_questa
cleanall_questa:
#	@rm -rf $(ALTERA_SIM_LIBS)
	@rm -f $(MS_INI) transcript autobackup*.do vsim_stacktrace.vstf
