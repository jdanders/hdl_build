#-*- makefile -*-
## ---------------- #
#  Xsim build rules #

ifndef TOP_SIM
  ifdef TOP_TB
## identify the top module to be simulated with `TOP_TB`. If not set, `TOP` will be used.
    TOP_SIM := $(TOP_TB)
  else
    ifdef TOP
      TOP_SIM := $(TOP)
    endif
  endif
endif

# To print variables that need full dependency includes
# for example: make printxsim-XSIM_LIB_LIST
.PHONY: printxsim-%
## use `make printxsim-VAR_NAME` to print variable after xsim processing
printxsim-%:
	@echo '$* = $($*)'


# Use this rule in a Makefile to force a recipe to execute before libraries
prexsimlib_hook := $(DONE_DIR)/prexsimlib_hook.done
## target hook to run before xsim libraries
$(prexsimlib_hook): | $(DONE_DIR)
	@touch $@

# Use this rule in a Makefile to force a recipe to execute before comp
prexcomp_hook := $(DONE_DIR)/prexcomp_hook.done
## target hook to run before compilation
$(prexcomp_hook): | $(DONE_DIR)
	@touch $@

# Use this rule in a Makefile to force a recipe to execute before simulation
prexsim_hook := $(DONE_DIR)/prexsim_hook.done
## target hook to run before starting xsim
$(prexsim_hook): | $(DONE_DIR)
	@touch $@


##################### Simulation Parameters ##############################

ifndef XSIM_SEED
  XSIM_SEED := 9149
endif

##### Upper Makefile simulation settings ####
## options for `xvlog` command
# XVLOG_OPTIONS : set in upper Makefile
## options for the `xelab` command
# XELAB_OPTIONS : set in upper Makefile
## options for `xsim` command
# XSIM_OPTIONS : set in upper Makefile

# Cannot be changed
XSIM_DIR := xsim.dir

XSIM_SUB_DONE := $(DONE_DIR)/xsim_substitutions.done
XSIM_LIB_DIR := $(XSIM_DIR)


##################### Module dependency targets ##############################

MAKEDEP_TOOL_XSIM := "xsim"
## a space delineated list of either `module:filename` mappings, or paths to a yaml file defining mappings. If a mapping is blank, dependency matching for the module is blocked. See `example-subs.yml`
# SIM_SUBSTITUTIONS: set in upper Makefile
ifdef SIM_SUBSTITUTIONS
  SUBS_XSIM := --subsfilelist '$(SIM_SUBSTITUTIONS)'
endif

# The .d (dependent) targets are to calculate the dependencies of a file
# The .d recipe is run whenever the sv file changes
# The sv dependency is added in the .d file itself
# The '%' becomes the module name
# The '$*' is replaced by that module name
$(DEP_DIR)/%.xsim.d: $(XSIM_SUB_DONE) $(predependency_hook) | $(DEP_DIR) $(BLOG_DIR)
	@if [ -d $(SRC_BASE_DIR) ]; then\
	  $(BUILD_SCRIPTS)/run_full_log_on_err.sh  \
	   "$(CLEAR)Identifying dependencies for $*$(UPDATE)" \
	   "$(MAKEDEPEND_CMD) $(SUBS_XSIM) $(MAKEDEP_TOOL_XSIM) $*" \
	   $(BLOG_DIR)/dependency_$*_xsim.log; \
	else \
	  echo -e "$(RED)Could not find SRC_BASE_DIR$(NC)"; false; \
	fi


##################### Include top level ##############################

# targets: grep lines that have ':', remove cleans, sed drop last character
# Extract all targets for xsim:
XSIM_TARGETS := $(shell grep -ohe "^[a-z].*:" $(HDL_BUILD_PATH)/xilinx/xsim.mk | grep -v clean | grep -v nuke | sed 's/:.*//')

# When the top .d file is included, make can't do anything until built.
# Make sure it's included only when needed to avoid doing extra work
XSIM_DEPS := $(filter $(XSIM_TARGETS),$(MAKECMDGOALS))
ifneq (,$(XSIM_DEPS))
  # The top .d file must be called out specifically to get the ball rolling
  # Otherwise nothing happens because there are no matches to the wildcard rule
  ifndef TOP_SIM
    $(error No TOP_SIM module defined)
  endif
  ifdef	TOP_SIM
    -include $(DEP_DIR)/$(TOP_SIM).xsim.d
  endif
endif


##################### Simulation Parameters ##############################

# Create list of libraries to use for xvlog and xsim
# In order to build in parallel, each module is in a separate lib
# Use _DEPS variable and replace ' ' with ' -L ', like: -L mod1 -L mod2
XSIM_TOP_DEPS := $(sort $(strip $($(TOP_SIM)_DEPS)))
XSIM_LIB_LIST := $(shell echo " $(XSIM_TOP_DEPS)" | sed -E 's| +(\w)| -L \1|g') -L work $(XSIM_LIB_APPEND)

## library string to appned to the library list, like `-L $(XSIM_LIB_DIR)/customlib`
# XSIM_LIB_APPEND : set in upper Makefile

# Gather all PARAM_ environment variables and make a parameter string
# First filter all variables to find all that start with PARAM_
MAKE_PARAMS := $(filter PARAM_%,$(.VARIABLES))
# Next change them from PARAM_NAME to NAME and grab their values
# This takes PARAM_NAME=value and changes it to -GNAME=value
XSIM_PARAM := $(foreach pname, $(MAKE_PARAMS),--generic_top "$(subst PARAM_,,$(pname))=$($(pname))")
PARAMETER_DONE := $(DONE_DIR)/parameters.done


##################### Dependency targets ##############################
# Create rules to determine dependencies and create compile recipes for .sv
.PHONY: deps
## target to figure out xsim dependencies only
deps: $(DEP_DIR)/$(TOP_SIM).xsim.d
.PHONY: comp
## target to compile simulation files
comp: $(DEP_DIR)/$(TOP_SIM).xsim.o $(prexcomp_hook)
.PHONY: filelist_xsim
## target to print list of files used in xsim
filelist_xsim: $(DEP_DIR)/$(TOP_SIM).xsim.d
	@grep "\.d:" $(DEP_DIR)/* | cut -d " " -f 2 | sort | uniq
.PHONY: modules_xsim
## target to print list of modules used in xsim
modules_xsim: $(DEP_DIR)/$(TOP_SIM).xsim.d
	@echo $(XSIM_TOP_DEPS)


# The .o (out) rules are to mark that the file has been compiled
# The .o recipe is used to compile all files
# The source file dependency is added in the .d file
# The "$*" is replaced with the stem, which is the module name
# The "$(word 1,$^)" is the second dependency, which will be the sv filename
XVLOG_INCLUDES := $(subst $\",,$(subst +incdir+,--include ,$(VLOG_INCLUDES)))
XVLOG_PARAMS := $(XVLOG_OPTIONS) $(XVLOG_INCLUDES)
XVLOG_CMD = xvlog -sv -work $* $(XVLOG_PARAMS) $(XSIM_LIB_LIST) $(word 1,$^)
XVLOG_MSG = $(CLEAR)Compiling $*$(UPDATE)
SVH_MSG = $(CLEAR)Including directory for $*$(UPDATE)
SVH_CMD = echo "$(COMP_MSG)"
$(DEP_DIR)/%.xsim.o: | $(DEP_DIR) $(BLOG_DIR)
	@if [ ! -f $(DEP_DIR)/$*.xsim.d ]; then echo -e "$(RED)Dependency .d file missing for $*$(NC)"; exit 1; fi
	@set -e; if  [[ $(word 1,$^) == *.svh || $(word 1,$^) == *.vh ]]; then \
	    $(HDL_BUILD_PATH)/xilinx/run_xilinx.sh '$(SVH_MSG)' '$(SVH_CMD)' '$(BLOG_DIR)/svh_$*.log'; \
	else if [[ $(word 1,$^) == *.sv || $(word 1,$^) == *.v ]]; then \
	    $(HDL_BUILD_PATH)/xilinx/run_xilinx.sh '$(XVLOG_MSG)' '$(XVLOG_CMD)' '$(BLOG_DIR)/xvlog_$*.log'; \
	else echo "Unknown filetype: $(word 1,$^)"; echo "$^"; exit 1; fi; fi;
	@touch $@



# The onfinish stop makes sure we can execute commands after run -all
# before the xsimulator exits.  Without that, if someone used a $finish
# at the end of their simulation the xsimulator would exit right after
# run -all and skip any commands that come after that.
BATCH_OPTIONS := --runall

# Compare against old results, and force update if different
ifeq ($(shell $(BUILD_SCRIPTS)/variable_change.sh "$(XSIM_PARAM)" $(PARAMETER_DONE)),yes)
XSIM_PARAM_DEP=$(PARAMETER_DONE).tmp
endif

##### Parameters ##
## monitors variables prefixed with **`PARAM_`** and passes them to xsimulator. `PARAM_NUM_PACKETS := 20` passes a parameter named NUM_PACKETS with value of 20.
# PARAM_*: set in upper Makefile

# Update the parameters if any of the PARAM_ variable change
$(PARAMETER_DONE).tmp: | $(DONE_DIR)
	@echo "$(XSIM_PARAM)" > $@
	@if [ ! -f $(PARAMETER_DONE) ]; then echo; echo "Recording PARAM_ parameters" && cp $@ $(PARAMETER_DONE); fi
$(PARAMETER_DONE): $(XSIM_PARAM_DEP)
	@-diff $@.tmp $@ >/dev/null 2>&1 \
	    && rm $@.tmp \
	    || (echo "Updating PARAM_ parameters" && mv $@.tmp $@);
	@touch $@


# Build dependencies for SIM_SUBSTITUTIONS variable
# Compare against old results, and force update if different
ifeq ($(shell $(BUILD_SCRIPTS)/variable_change.sh "$(SIM_SUBSTITUTIONS)" $(XSIM_SUB_DONE)),yes)
XSIMSUB_DEP=$(XSIM_SUB_DONE).tmp
endif

# Update the substitutions if the SIM_SUBSTITUTIONS variable changes
$(XSIM_SUB_DONE).tmp: | $(DONE_DIR)
	@echo "$(SIM_SUBSTITUTIONS)" > $@
	@if [ ! -f $(XSIM_SUB_DONE) ]; then echo "Recording SIM_SUBSTITUTIONS" && cp $@ $(XSIM_SUB_DONE); fi
$(XSIM_SUB_DONE): $(XSIMSUB_DEP)
	@-diff $@.tmp $@ >/dev/null 2>&1 \
	    && rm $@.tmp \
	    || (echo "Updating SIM_SUBSTITUTIONS" && mv $@.tmp $@);
	@touch $@


WDB_PARAM := --wdb $(BLD_DIR)/xsim.wdb
XELAB_PARAMS := $(XSIM_PARAM) $(XELAB_OPTIONS) $(XSIM_LIB_LIST) --debug all
XSIM_PARAMS := --sv_seed $(XSIM_SEED) $(WDB_PARAM) $(XSIM_OPTIONS) $(XSIM_PARAM)
XELAB_CMD := xelab $(XELAB_PARAMS) $(TOP_SIM).$(TOP_SIM)

##################### Do command targets ##############################
.PHONY: elab_sim
## target to run elaboration batch
elab_sim: $(DONE_DIR)/elab_sim
$(DONE_DIR)/elab_sim: $(PARAMETER_DONE) $(DEP_DIR)/$(TOP_SIM).xsim.o $(prexsim_hook)
	@echo -e "$O Elaborating simulation $C (see $(BLOG_DIR)/elab.log)"
	@$(HDL_BUILD_PATH)/xilinx/run_xilinx.sh "xelab $(TOP_SIM)" \
	 "$(XELAB_CMD)" "$(BLOG_DIR)/elab.log"
	@touch $(DONE_DIR)/elab_sim

.PHONY: sim
# to run make commands cleanly in GUI, remove -j flags
## target to run simulation in GUI
sim: $(PARAMETER_DONE) $(DONE_DIR)/elab_sim $(prexsim_hook)
	@echo -e "$O Starting simulation $C"
	MAKEFLAGS="-r" xsim $(XSIM_PARAMS) $(TOP_SIM).$(TOP_SIM) --gui &

.PHONY: batch
## target to run simulation batch
batch: $(PARAMETER_DONE) comp $(prexsim_hook)
	@echo -e "$O Starting batch simulation $C (see $(BLOG_DIR)/batch.log)"
	@if $(HDL_BUILD_PATH)/xilinx/run_xilinx.sh "xelab $(TOP_SIM) $(BATCH_OPTIONS)" \
	 "$(XELAB_CMD) $(BATCH_OPTIONS)" "$(BLOG_DIR)/batch.log"; then \
	     echo -e "$(GREEN)# Simulation successful $C"; \
	 else false; \
	 fi
	@touch $(DONE_DIR)/elab_sim


.PHONY: clean
clean: clean_xsim
cleanall: clean_xsim
.PHONY: clean_xsim
clean_xsim:
	@rm -rf $(XSIM_LIB_DIR) $(WORK) webtalk*.jou xsim*.jou xelab*.jou xvlog*.jou webtalk*.log xsim*.log xelab*.log xvlog*.log xelab*.pb xvlog*.pb *.wdb
	@if [[ "$(MAKECMDGOALS)" == *comp* ]]; then make --no-print-directory -r $(DEP_DIR)/$(TOP_SIM).d; fi
