#-*- makefile -*-
#--- Modelsim build rules: ## ----------------

# To print variables that need full dependency includes
# for example: make printmodelsim-SIM_LIB_LIST
.PHONY: printmodelsim-%
printmodelsim-%: ## use 'make printmodelsim-VAR_NAME' to print variable after modelsim processing
	@echo '$* = $($*)'

SIM_LIB_DONE := $(DONE_DIR)/sim_lib_map
SIM_SUB_DONE := $(DONE_DIR)/sim_substitutions.done
SIM_LIB_DIR := $(BLD_DIR)/simlib


##################### Module dependency targets ##############################

MAKEDEP_TOOL_MODELSIM := "modelsim"
ifdef SIM_SUBSTITUTIONS
  SUBS_MODELSIM := --subsfilelist '$(SIM_SUBSTITUTIONS)'
endif

# The .d (dependent) targets are to calculate the dependencies of a file
# The .d recipe is run whenever the sv file changes
# The sv dependency is added in the .d file itself
# The '%' becomes the module name
# The '$*' is replaced by that module name
$(DEP_DIR)/%.modelsim.d: $(SIM_SUB_DONE) $(predependency_hook) | $(DEP_DIR) $(BLOG_DIR)
	@if [ -d "$(SRC_BASE_DIR)" ]; then\
	  $(BUILD_SCRIPTS)/run_full_log_on_err.sh  \
	   "$(CLEAR)Identifying dependencies for $*$(UPDATE)" \
	   "$(MAKEDEPEND_CMD) $(SUBS_MODELSIM) $(MAKEDEP_TOOL_MODELSIM) $*" \
	   $(BLOG_DIR)/dependency_$*_modelsim.log; \
	else \
	  echo -e "$(RED)Could not find SRC_BASE_DIR$(NC)"; false; \
	fi


##################### Include top level ##############################

# targets: grep lines that have ':', remove cleans, sed drop last character
# Extract all targets for sim:
MODELSIM_TARGETS := $(shell grep -ohe "^[a-z].*:" $(HDL_BUILD_PATH)/siemens/modelsim.mk $(HDL_BUILD_PATH)/siemens/siemens_common.mk | grep -v clean | grep -v nuke | sed 's/:.*//')

# When the top .d file is included, make can't do anything until built.
# Make sure it's included only when needed to avoid doing extra work
SIM_DEPS := $(filter $(MODELSIM_TARGETS),$(MAKECMDGOALS))
ifneq (,$(SIM_DEPS))
  # The top .d file must be called out specifically to get the ball rolling
  # Otherwise nothing happens because there are no matches to the wildcard rule
  ifndef TOP_TB
    $(error No TOP_TB module defined)
  endif
  ifdef	TOP_TB
    -include $(DEP_DIR)/$(TOP_TB).modelsim.d
  endif
endif


##################### Simulation Parameters ##############################

SUPRESS_PARAMS := +nowarnTFMPC

MSIM_VOPT := $(SUPRESS_PARAMS) $(strip +acc $(VOPT_OPTIONS))

DEFAULT_SIM_LIB :=

MS_INI := $(BLD_DIR)/modelsim.ini
MS_INI_PARAM := -modelsimini $(MS_INI)

# Create list of libraries to use for vlog and vsim
# In order to build in parallel, each module is in a separate lib
# Use _DEPS variable and replace ' ' with ' -L ', like: -L mod1 -L mod2
SIM_TOP_DEPS := $(sort $(strip $($(TOP_TB)_DEPS)))
SIM_LIB_LIST := $(shell echo " $(SIM_TOP_DEPS)" | sed -E 's| +(\w)| -L \1|g') -L work $(SIM_LIB_APPEND)

# Gather all PARAM_ environment variables and make a parameter string
# First filter all variables to find all that start with PARAM_
MAKE_PARAMS := $(filter PARAM_%,$(.VARIABLES))
# Next change them from PARAM_NAME to NAME and grab their values
# This takes PARAM_NAME=value and changes it to -GNAME=value
SIM_PARAM := $(foreach pname, $(MAKE_PARAMS),-G$(subst PARAM_,,$(pname))=$($(pname)))

##################### Dependency targets ##############################
# Create rules to determine dependencies and create compile recipes for .sv
.PHONY: deps
deps: $(DEP_DIR)/$(TOP_TB).modelsim.d ## Figure out sim dependencies only
.PHONY: comp
comp: $(MS_INI) $(DEP_DIR)/$(TOP_TB).modelsim.o $(precomp_hook) ## Compile simulation files
.PHONY: filelist_sim
filelist_sim: $(DEP_DIR)/$(TOP_TB).modelsim.d ## print list of files used in sim
	@grep "\.d:" $(DEP_DIR)/* | cut -d " " -f 2 | sort | uniq
.PHONY: modules_sim
modules_sim: $(DEP_DIR)/$(TOP_TB).modelsim.d ## print list of modules used in sim
	@echo $(SIM_TOP_DEPS)


# The .o (out) rules are to mark that the file has been compiled
# The .o recipe is used to compile all files
# The source file dependency is added in the .d file
# The "$*" is replaced with the stem, which is the module name
# The "$(word 2,$^)" is the second dependency, which will be the sv filename
VLOG_CMD = vlog -sv -work $(SIM_LIB_DIR)/$* $(VLOG_PARAMS) $(DEFAULT_SIM_LIB) $(SIM_LIB_LIST) $(word 2,$^)
VLOG_MSG = $(CLEAR)Compiling $*$(UPDATE)
SVH_MSG = $(CLEAR)Including directory for $*$(UPDATE)
SVH_CMD = echo "$(COMP_MSG)"
$(DEP_DIR)/%.modelsim.o: $(SIM_LIB_DONE) | $(DEP_DIR) $(BLOG_DIR)
	@if [ ! -f $(DEP_DIR)/$*.modelsim.d ]; then echo -e "$(RED)Dependency .d file missing for $*$(NC)"; exit 1; fi
	@set -e; if  [[ $(word 2,$^) == *.svh || $(word 2,$^) == *.vh ]]; then \
	    $(HDL_BUILD_PATH)/siemens/run_siemens.sh '$(SVH_MSG)' '$(SVH_CMD)' '$(BLOG_DIR)/svh_$*.log'; \
	else if [[ $(word 2,$^) == *.sv || $(word 2,$^) == *.v ]]; then \
	    $(HDL_BUILD_PATH)/siemens/run_siemens.sh '$(VLOG_MSG)' '$(VLOG_CMD)' '$(BLOG_DIR)/vlog_$*.log'; \
	else echo "Unknown filetype: $(word 2,$^)"; echo "$^"; exit 1; fi; fi;
	@touch $@


PRESIM_GOAL := comp
TOP_COMP := $(TOP_TB)

include $(HDL_BUILD_PATH)/siemens/siemens_common.mk
