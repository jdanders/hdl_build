#-*- makefile -*-
## ----------------- #
# Questa build rules #

ifndef TOP_SIM
  ifdef TOP_TB
## identify the top module to be simulated with `TOP_SIM`. If not set, `TOP` will be used.
    TOP_SIM := $(TOP_TB)
  else
    ifdef TOP
      TOP_SIM := $(TOP)
    endif
  endif
endif

SIM_LIB_DONE := $(DONE_DIR)/sim_lib_map
SIM_SUB_DONE := $(DONE_DIR)/sim_substitutions.done
SIM_LIB_DIR := $(BLD_DIR)/simlib
AC_SCRIPT := $(BLD_DIR)/ac.do
AC_OUT_DIR := $(BLD_DIR)/ac_output
AC_REPORT := $(AC_OUT_DIR)/autocheck_verify.rpt
AC_DONE := $(DONE_DIR)/ac.done

##################### Module dependency targets ##############################

MAKEDEP_TOOL_QUESTA := "questa"
## a space delineated list of either `module:filename` mappings, or paths to a yaml file defining mappings. If a mapping is blank, dependency matching for the module is blocked. See `examples/example-subs.yml`. For example: `SIM_SUBSTITUTIONS = $(shell git_root_path sim_models/sim_all_ipcores.yml) eth_1g:$(shell git_root_path sim_models/1g_sim_model.sv ignorememodule:`
# SIM_SUBSTITUTIONS: set in upper Makefile
ifdef SIM_SUBSTITUTIONS
  SUBS_QUESTA := --subsfilelist '$(SIM_SUBSTITUTIONS)'
endif

# The .d (dependent) targets are to calculate the dependencies of a file
# The .d recipe is run whenever the sv file changes
# The sv dependency is added in the .d file itself
# The '%' becomes the module name
# The '$*' is replaced by that module name
$(DEP_DIR)/%.questa.d: $(SIM_SUB_DONE) $(predependency_hook) | $(DEP_DIR) $(BLOG_DIR)
	@if [ -d $(SRC_BASE_DIR) ]; then\
	  $(BUILD_SCRIPTS)/run_full_log_on_err.sh  \
	   "$(CLEAR)Identifying dependencies for $*$(UPDATE)" \
	   "$(MAKEDEPEND_CMD) $(SUBS_QUESTA) $(MAKEDEP_TOOL_QUESTA) $*" \
	   $(BLOG_DIR)/dependency_$*_questa.log; \
	else \
	  echo -e "$(RED)Could not find SRC_BASE_DIR$(NC)"; false; \
	fi


##################### Include top level ##############################

# targets: grep lines that have ':', remove cleans, sed drop last character
# Extract all targets for sim:
QUESTA_TARGETS := $(shell grep -ohe "^[a-z].*:" $(HDL_BUILD_PATH)/siemens/*.mk | grep -v clean | grep -v nuke | sed 's/:.*//')
AC_TARGETS := ac ac_batch autocheck autocheck_batch

# When the top .d file is included, make can't do anything until built.
# Make sure it's included only when needed to avoid doing extra work
SIM_DEPS := $(filter $(QUESTA_TARGETS),$(MAKECMDGOALS))
ifneq (,$(SIM_DEPS))
  # The top .d file must be called out specifically to get the ball rolling
  # Otherwise nothing happens because there are no matches to the wildcard rule
  ifndef TOP_SIM
    $(error No TOP_SIM module defined)
  endif
  ifdef TOP_SIM
    -include $(DEP_DIR)/$(TOP_SIM).questa.d
    SIEMENS_TOP := $(TOP_SIM)
  endif
endif

AC_DEPS := $(filter $(AC_TARGETS),$(MAKECMDGOALS))
ifneq (,$(AC_DEPS))
  ifndef TOP_AC
    $(error No TOP_AC module defined)
  endif
  ifdef TOP_AC
    -include $(DEP_DIR)/$(TOP_AC).questa.d
    SIEMENS_TOP := $(TOP_AC)
  endif
endif

##################### Simulation Parameters ##############################

VOPT_DONE := $(DONE_DIR)/vopt.done

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

SUPPRESS_PARAMS := +nowarnTFMPC

MS_INI := $(BLD_DIR)/modelsim.ini
MS_INI_PARAM := -modelsimini $(MS_INI)

VOPT_PARAMS := $(SUPPRESS_PARAMS) $(MS_INI_PARAM) $(strip +acc $(VOPT_OPTIONS))

# Create list of libraries to use for vlog and vsim
# In order to build in parallel, each module is in a separate lib
# Use _DEPS variable and replace ' ' with ' -L ', like: -L mod1 -L mod2
SIM_TOP_DEPS := $(sort $(strip $($(SIEMENS_TOP)_DEPS)))
SIM_LIB_LIST := $(shell echo " $(SIM_TOP_DEPS)" | sed -E 's| +(\w)| -L \1|g') -L work $(SIM_LIB_APPEND)

## library string to appned to the library list, like `-L $(SIM_LIB_DIR)/customlib`
# SIM_LIB_APPEND : set in upper Makefile

# Gather all PARAM_ environment variables and make a parameter string
# First filter all variables to find all that start with PARAM_
MAKE_PARAMS := $(filter PARAM_%,$(.VARIABLES))
# Next change them from PARAM_NAME to NAME and grab their values
# This takes PARAM_NAME=value and changes it to -GNAME=value
SIM_PARAM := $(foreach pname, $(MAKE_PARAMS),-G$(subst PARAM_,,$(pname))=$($(pname)))
PARAMETER_DONE := $(DONE_DIR)/parameters.done

##################### Dependency targets ##############################
# Create rules to determine dependencies and create compile recipes for .sv
.PHONY: deps
## target to figure out sim dependencies only
deps: $(DEP_DIR)/$(SIEMENS_TOP).questa.d
.PHONY: comp
## target to compile simulation files
comp: $(MS_INI) $(DEP_DIR)/$(SIEMENS_TOP).questa.o $(precomp_hook)
.PHONY: vopt
## target to perform vopt after compile
vopt: comp $(VOPT_DONE)
.PHONY: filelist_sim
## target to print list of files used in sim
filelist_sim: $(DEP_DIR)/$(SIEMENS_TOP).questa.d
	@grep "\.d:" $(DEP_DIR)/* | cut -d " " -f 2 | sort | uniq
.PHONY: modules_sim
## target to print list of modules used in sim
modules_sim: $(DEP_DIR)/$(SIEMENS_TOP).questa.d
	@echo $(SIM_TOP_DEPS)

# TODO: On some simulations, vopt fails the first time. FIXME!
# for example: cedarbreaks/tie_fpga/tie_system_sim/build_bad_ip_frag
VOPT_CMD := "vopt -sv -work $(SIM_LIB_DIR)/$(SIEMENS_TOP) $(VOPT_PARAMS) $(SIM_LIB_LIST) $(SIM_PARAM) $(SIM_LIB_DIR)/$(SIEMENS_TOP).$(SIEMENS_TOP) -o $(SIEMENS_TOP)_opt"
VOPT_MSG := "$O Optimizing design $C (see $(BLOG_DIR)/vopt.log)"

$(VOPT_DONE): $(DEP_DIR)/$(SIEMENS_TOP).questa.o $(PARAMETER_DONE) | $(DONE_DIR)
	@$(BUILD_SCRIPTS)/run_print_warn_and_err.sh $(VOPT_MSG) $(VOPT_CMD) $(BLOG_DIR)/vopt.log \
	 || (echo -e "$O Only a problem if second vopt attempt fails... $C" && $(BUILD_SCRIPTS)/run_print_warn_and_err.sh  $(VOPT_MSG) $(VOPT_CMD) $(BLOG_DIR)/vopt.log)
	@touch $(VOPT_DONE)


# The .o (out) rules are to mark that the file has been compiled
# The .o recipe is used to compile all files
# The source file dependency is added in the .d file
# The "$*" is replaced with the stem, which is the module name
# The "$(word 2,$^)" is the second dependency, which will be the sv filename
VLOG_CMD = vlog -sv -work $(SIM_LIB_DIR)/$* $(VLOG_PARAMS) $(SIM_LIB_LIST) $(word 2,$^)
VLOG_MSG = $(CLEAR)Compiling $*$(UPDATE)
SVH_MSG = $(CLEAR)Including directory for $*$(UPDATE)
SVH_CMD = echo "$(COMP_MSG)"
$(DEP_DIR)/%.questa.o: $(SIM_LIB_DONE) | $(DEP_DIR) $(BLOG_DIR)
	@if [ ! -f $(DEP_DIR)/$*.questa.d ]; then echo -e "$(RED)Dependency .d file missing for $*$(NC)"; exit 1; fi
	@set -e; if  [[ $(word 2,$^) == *.svh || $(word 2,$^) == *.vh ]]; then \
	    $(HDL_BUILD_PATH)/siemens/run_siemens.sh '$(SVH_MSG)' '$(SVH_CMD)' '$(BLOG_DIR)/svh_$*.log'; \
	else if [[ $(word 2,$^) == *.sv || $(word 2,$^) == *.v ]]; then \
	    $(HDL_BUILD_PATH)/siemens/run_siemens.sh '$(VLOG_MSG)' '$(VLOG_CMD)' '$(BLOG_DIR)/vlog_$*.log'; \
	else echo "Unknown filetype: $(word 2,$^)"; echo "$^"; exit 1; fi; fi;
	@touch $@

ifndef AC_DIRECTIVES
## Autocheck directives filename, default is ac_directives.tcl
  AC_DIRECTIVES := ac_directives.tcl
endif

AC_CMD := qverify -c -do $(AC_SCRIPT) -od $(AC_OUT_DIR) -modelsimini $(MS_INI)
AC_MSG := $O Starting autocheck simulation $C (see $(BLOG_DIR)/autocheck.log)
$(AC_DONE): $(MS_INI) $(DEP_DIR)/$(SIEMENS_TOP).questa.o $(precomp_hook) $(AC_DIRECTIVES)
	@printf "$(autocheck_str)" > $(AC_SCRIPT)
	@$(HDL_BUILD_PATH)/siemens/run_siemens.sh '$(AC_MSG)' '$(AC_CMD)' '$(BLOG_DIR)/autocheck.log';
	@touch $@

PRESIM_GOAL := vopt
TOP_COMP := $(SIEMENS_TOP)_opt

# To print variables that need full dependency includes
# for example: make printquesta-SIM_LIB_LIST
.PHONY: printquesta-%
## use `make printquesta-VAR_NAME` to print variable after questa processing
printquesta-%:
	@echo '$* = $($*)'

include $(HDL_BUILD_PATH)/siemens/siemens_common.mk
