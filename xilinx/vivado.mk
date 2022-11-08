#-*- makefile -*-
## ------------------- #
#  Vivado build rules #

ifndef TOP_SYNTH
  ifdef TOP
## identify the top module to be simulated with `TOP_SYNTH`. If not set, `TOP` will be used.
    TOP_SYNTH := $(TOP)
  endif
endif

## identify the FPGA device part number, should match string in project settings
# DEVICE: set in upper Makefile

presynth_hook := $(DONE_DIR)/presynth_hook.done
## target hook to run before any synth work
$(presynth_hook): | $(DONE_DIR)
	@touch $@

post_gen_ip_hook := $(DONE_DIR)/post_gen_ip_hook.done
## target hook to run after ip generation is done, before mapping
$(post_gen_ip_hook): $(DONE_DIR)/gen_ip.done | $(DONE_DIR)
	@touch $@

SYNTH_SUB_DONE := $(DONE_DIR)/synth_substitutions.done

# To print variables that need full dependency includes
.PHONY: printvivado-%
## use `make printvivado-VAR_NAME` to print variable after Vivado processing
printvivado-%:
	@echo '$* = $($*)'

## synthesis enforces `SYNTH_TOOL` version match against tool on `PATH`. Run make with `SYNTH_OVERRIDE=1` to ignore the check.
# SYNTH_OVERRIDE: set in upper Makefile

export VIVADO_VERSION_FOUND := $(shell vivado -version | grep Vivado | awk '{print substr($$2,2)}')

# Recipe to always run
.PHONY: always_run
always_run:
	@ if [[ "$(SYNTH_OVERRIDE)" != "y" ]]; then \
	    if [[ $(VIVADO_VERSION) != $(VIVADO_VERSION_FOUND) ]]; then \
	      echo -e "ERROR: $(RED)Vivado version $(VIVADO_VERSION_FOUND) found but $(VIVADO_VERSION) is set $(NC)\n (prefix with SYNTH_OVERRIDE=y to override)"; false; \
	fi; fi


SYNTH_DIR := $(BLD_DIR)/$(TOP_SYNTH)
PROJECT := $(SYNTH_DIR)/$(TOP_SYNTH)
IP_DIR := $(CURDIR)/$(BLD_DIR)/ip_cores
IP_MK := $(IP_DIR)/ip.mk
TCL_DIR := $(BLD_DIR)/tcl
FILES_TCL := $(TCL_DIR)/include_files.tcl
PARAMETER_TCL := $(TCL_DIR)/parameters.tcl
SYNTH_TCL := $(TCL_DIR)/synth.tcl
IMPL_TCL := $(TCL_DIR)/impl.tcl
BITGEN_TCL := $(TCL_DIR)/bitgen.tcl
GIT_INFO_FILE := $(SYNTH_DIR)/git_info.txt
NOTHING_DEP := $(DONE_DIR)/nothing.done
TIMING_RPT_FILE := $(SYNTH_DIR)/TQ_timing_report.txt
DATE := `date \"+%a %H:%M:%S\"`


##################### Module dependency targets ##############################

MAKEDEP_TOOL_VIVADO := "vivado"

## a space delineated list of either `module:filename` mappings, or paths to a yaml file defining mappings. If a mapping is blank, dependency matching for the module is blocked. See `examples/example-subs.yml`. For example: `SYNTH_SUBSTITUTIONS = $(shell git_root_path mocks/s10_mocks.yml) eth_100g:$(shell git_root_path mocks/100g_core.ip simonly_check:`
# SYNTH_SUBSTITUTIONS: set in upper Makefile
ifdef SYNTH_SUBSTITUTIONS
  SUBS_VIVADO := --subsfilelist '$(SYNTH_SUBSTITUTIONS)'
  SUBS_VIVADO_MODULES := "$(shell $(BUILD_SCRIPTS)/list_substitutions.py $(SRC_BASE_DIR) '$(SYNTH_SUBSTITUTIONS)')"
endif

# The .d (dependent) targets are to calculate the dependencies of a file
# The .d recipe is run whenever the sv file changes
# The sv dependency is added in the .d file itself
# The '%' becomes the module name
# The '$*' is replaced by that module name
$(DEP_DIR)/%.vivado.d: $(SYNTH_SUB_DONE) $(predependency_hook) | $(DEP_DIR) $(BLOG_DIR)
	@if [ -d $(SRC_BASE_DIR) ]; then\
	  $(BUILD_SCRIPTS)/run_full_log_on_err.sh  \
	   "Identifying dependencies for $*$(UPDATE)" \
	   "$(MAKEDEPEND_CMD) $(SUBS_VIVADO) $(MAKEDEP_TOOL_VIVADO) $*" \
	   $(BLOG_DIR)/dependency_$*_vivado.log; \
	else \
	  echo -e "$(RED)Could not find SRC_BASE_DIR$(NC)"; false; \
	fi


##################### Include top level ##############################

# targets: grep lines that have ':', remove exceptions, sed drop last character
# Extract all targets for synthesis that need dependency analysis:
VIVADO_TARGETS := $(shell grep -oe "^[a-z].*:" $(HDL_BUILD_PATH)/xilinx/vivado.mk | grep -v clean | grep -v nuke | grep -v archive_synth_results | sed 's/:.*//')

# When the top .d file is included, make can't do anything until built.
# Make sure it's included only when needed to avoid doing extra work
SYNTH_DEPS := $(filter $(VIVADO_TARGETS),$(MAKECMDGOALS))
ifneq (,$(SYNTH_DEPS))
  # The top .d file must be called out specifically to get the ball rolling
  # Otherwise nothing happens because there are no matches to the wildcard rule
  ifndef TOP_SYNTH
    $(error No TOP_SYNTH module defined)
  endif
  ifdef	TOP_SYNTH
    -include $(DEP_DIR)/$(TOP_SYNTH).vivado.d
    -include $(IP_MK)
    $(BLD_DIR): always_run
  endif
endif


##################### Synthesis Parameters ##############################
SYNTH_TOP_DEPS := $(sort $(strip $($(TOP_SYNTH)_DEPS)))

# SYNTH_ARGS: Set in upper Makefile
VIVADO_BATCH := vivado -mode batch -log $(PROJECT).log -journal $(PROJECT).jou


## file paths to xdc constraints files that will be used in the build
# XDC_FILES: set in upper Makefile
XDC_DONE := $(DONE_DIR)/xdc.done

##################### Directory targets ##############################
$(SYNTH_DIR): | $(BLD_DIR)
	@mkdir -p $(SYNTH_DIR)

$(IP_DIR): | $(BLD_DIR)
	@mkdir -p $(IP_DIR)

$(TCL_DIR): | $(BLD_DIR)
	@mkdir -p $(TCL_DIR)


##################### Dependency targets ##############################
# Create rules to determine dependencies and create compile recipes for .sv
.PHONY: filelist_synth
## print list of files used in synth
filelist_synth: $(DEP_DIR)/$(TOP_SYNTH).vivado.d
	@grep "\.d:" $(DEP_DIR)/* | cut -d " " -f 2 | sort | uniq
.PHONY: modules_synth
## print list of modules used in synth
modules_synth: $(DEP_DIR)/$(TOP_SYNTH).vivado.d
	@echo $(SYNTH_TOP_DEPS)

$(NOTHING_DEP): | $(DONE_DIR)
	@touch $@


# the .o files will write to individual files, so cat together into one file
$(FILES_TCL): $(SYNTH_SUB_DONE) $(presynth_hook) $(DEP_DIR)/$(TOP_SYNTH).vivado.o | $(DEP_DIR) $(TCL_DIR)
	@cat $(FILES_TCL).* > $@
	@touch $@

##### Parameters ##
## monitors variables prefixed with **`PARAM_`** and passes them to Vivado. `PARAM_NUM_PORTS := 2` passes a parameter named NUM_PORTS with value of 2.
# PARAM_*: set in upper Makefile

# Gather all PARAM_ environment variables and make a parameter string
# First filter all variables to find all that start with PARAM_
MAKE_PARAMS := $(filter PARAM_%,$(.VARIABLES))
# Next change them from PARAM_NAME to NAME and grab their values
# Output for PARAM_NAME=value: -generic NAME=value
# These are added to the synth command
TCL_PARAM := $(foreach pname, $(MAKE_PARAMS),-generic $(subst PARAM_,,$(pname))=$($(pname)))



# Compare against old results, and force update if different
ifeq ($(shell $(BUILD_SCRIPTS)/variable_change.sh "$(TCL_PARAM)" $(PARAMETER_TCL)),yes)
SYNTH_PARAM_DEP=$(PARAMETER_TCL).tmp
endif

# Update the parameters if any of the PARAM_ variable change
$(PARAMETER_TCL).tmp: | $(TCL_DIR)
	@echo "$(TCL_PARAM)" > $@
	@if [ ! -f $(PARAMETER_TCL) ]; then echo; echo "Recording PARAM_ parameters" && cp $@ $(PARAMETER_TCL); fi
$(PARAMETER_TCL): $(SYNTH_PARAM_DEP)
	@-diff $@.tmp $@ >/dev/null 2>&1 \
	    && rm $@.tmp \
	    || (echo; echo "Updating PARAM_ parameters" && mv $@.tmp $@);
	@touch $@

# Make string for tcl script to read in all XDC_FILES
TCL_XDC := $(foreach xdc_path, $(XDC_FILES),read_xdc $(xdc_path))

# Compare against old results, and force update if different
ifeq ($(shell $(BUILD_SCRIPTS)/variable_change.sh "$(XDC_FILES)" $(XDC_DONE)),yes)
XDC_DEP=$(XDC_DONE).tmp
endif
# Update the parameters if any of the PARAM_ variable change
$(XDC_DONE).tmp: | $(DONE_DIR)
	@echo "$(XDC_FILES)" > $@
	@if [ ! -f $(XDC_DONE) ]; then echo; echo "Recording XDC_FILES" && cp $@ $(XDC_DONE); fi
$(XDC_DONE): $(XDC_DEP)
	@if [ ! -f $@.tmp ]; then echo "$(XDC_FILES)" > $@.tmp; fi
	@-diff $@.tmp $@ >/dev/null 2>&1 \
	    && rm $@.tmp \
	    || (echo; echo "Updating XDC_FILES" && mv $@.tmp $@);
	@touch $@

# Build dependencies for SYNTH_SUBSTITUTIONS variable
# Compare against old results, and force update if different
ifeq ($(shell $(BUILD_SCRIPTS)/variable_change.sh "$(SYNTH_SUBSTITUTIONS)" $(SYNTH_SUB_DONE)),yes)
SYNTHSUB_DEP=$(SYNTH_SUB_DONE).tmp
endif

# Update the substitutions if the SYNTH_SUBSTITUTIONS variable changes
$(SYNTH_SUB_DONE).tmp: | $(DONE_DIR)
	@echo "$(SYNTH_SUBSTITUTIONS)" > $@
	@if [ ! -f $(SYNTH_SUB_DONE) ]; then echo "Recording SYNTH_SUBSTITUTIONS" && cp $@ $(SYNTH_SUB_DONE); fi
$(SYNTH_SUB_DONE): $(SYNTHSUB_DEP)
	@-diff $@.tmp $@ >/dev/null 2>&1 \
	    && rm $@.tmp \
	    || (echo "Updating SYNTH_SUBSTITUTIONS" && mv $@.tmp $@ && rm $(DEP_DIR)/*.vivado.o);
	@touch $@


# The .o (out) rules are to mark that the file has been compiled
# The .o recipe is used to compile all files
# The source file dependency is added in the .d file
# The "$*" is replaced with the stem, which is the module name
# The "$(word 2,$^)" is the second dependency, which will be the sv filename
# ftype is the filename suffix with out the leading '.'
# TODO: The `if fpath` and NOTHING_DEP below is to quiet a false try cause by including $(IP_MK)
#   For some reason this recipe is called before the files are written
#   This shouldn't be needed -- figure out how to prevent it and remove `if`

# synth_commands.mk includes all the commands run below
# fpath, ftype, fdir, and ipsearch are used in synth_commands.mk
include $(HDL_BUILD_PATH)/xilinx/synth_commands.mk
COMP_MSG = $(CLEAR)Adding $*$(UPDATE)
$(DEP_DIR)/%.vivado.o:  $(NOTHING_DEP) | $(DONE_DIR) $(DEP_DIR) $(BLOG_DIR) $(IP_DIR) $(TCL_DIR)
	$(eval fpath = $(word 2,$^))
	$(eval ftype = $(subst .,,$(suffix $(word 2,$^))))
	$(eval fdir = $(dir $(fpath)))
	@set -e; if [ "$(fpath)" ]; then\
	  if [ ! -f $(DEP_DIR)/$*.vivado.d ]; then \
	    echo -e "$(RED)Dependency .d file missing for $*$(NC), missing source file?"; false;\
	  fi; \
	  if  [[ "$(fpath)" == *.v || "$(fpath)" == *.sv || "$(fpath)" == *.svh || "$(fpath)" == *.vh ]]; then \
	      $(HDL_BUILD_PATH)/xilinx/run_xilinx.sh '$(COMP_MSG)' '$(sv_cmd)' '$(BLOG_DIR)/sv_vivado_$*.log'; \
	  else if [[ "$(fpath)" == *.xci ]]; then \
	      $(HDL_BUILD_PATH)/xilinx/run_xilinx.sh '$(COMP_MSG)' '$(xci_cmd)' '$(BLOG_DIR)/xci_vivado_$*.log'; \
	  else if [[ "$(fpath)" == *.xcix ]]; then \
	      $(HDL_BUILD_PATH)/xilinx/run_xilinx.sh '$(COMP_MSG)' '$(xcix_cmd)' '$(BLOG_DIR)/xcix_vivado_$*.log'; \
	  else echo "Unknown filetype: $(fpath)"; echo "$^"; exit 1; fi; fi; fi;\
	  touch $@; \
	else false; fi


##################### Project targets ##############################
# Create rules to create inputs to tcl script files
# SYNTH_ARGS: Set in upper Makefile
# OPT_DESIGN_ARGS: Set in upper Makefile
# PLACE_DESIGN_ARGS: Set in upper Makefile
# PHYS_OPT_DESIGN_ARGS: Set in upper Makefile
# ROUTE_DESIGN_ARGS: Set in upper Makefile

include $(HDL_BUILD_PATH)/xilinx/synth_tcl.mk
$(SYNTH_TCL): $(FILES_TCL) $(PARAMETER_TCL) $(XDC_DONE) | $(TCL_DIR) $(SYNTH_DIR)
	@echo -e "$(synth_path)" > $@
	@cat $(FILES_TCL) >> $@
	@echo -e "$(TCL_XDC)" >> $@
	@echo -e "$(synth_start)" >> $@
	@touch $@

$(IMPL_TCL): | $(TCL_DIR) $(SYNTH_DIR)
	@echo -e "$(synth_impl)" > $@
	@touch $@

$(BITGEN_TCL): | $(TCL_DIR) $(SYNTH_DIR)
	@echo -e "$(synth_bitgen)" > $@
	@touch $@

.PHONY: project
## target to create Vivado project
# TODO: Create a project flow
project: $(SYNTH_TCL)


# Log relevant repo information before building
$(DONE_DIR)/git.rpt: $(SYNTH_TCL) | $(DONE_DIR)
	@touch $@

.PHONY: git_info
## target to archive git info in project directory
git_info: $(GIT_INFO_FILE)
$(GIT_INFO_FILE): $(DONE_DIR)/git.rpt | $(SYNTH_DIR)
ifdef GIT_REPO
	@echo -e "Saving git repository information in $@"
	@-git config user.name > $@
	@-echo $(shell whoami)@$(shell hostname):$(shell pwd) >> $@
	@-echo "source repo   : $$(git rev-parse HEAD)" >> $@
	@-cd $(HDL_BUILD_PATH) && echo "hdl_build repo: $$(git rev-parse HEAD)" >> $(abspath $@)
	@-git status >> $@
	@-git diff -b >> $@
	@-git diff -b --cached >> $@
	@-git log -10 --pretty=format:'%h %s <%an>' >> $@
endif
	@touch $@


##################### Synthesis targets ##############################
# Create rules to determine which steps of synthesis need to be done
$(IP_MK): $(SYNTH_TCL)
	@if ls $@.* >/dev/null 2>&1; then cat $@.* > $@; fi
	@touch $@

.PHONY: ipgen
## target to generate Xilinx IP
ipgen: $(DONE_DIR)/gen_ip.done | $(DONE_DIR)
# IP rules are built up in $(IP_MK)
$(DONE_DIR)/gen_ip.done: $(IP_MK)
	@touch $@


$(DONE_DIR)/synth_ready.done: $(DONE_DIR)/gen_ip.done $(GIT_INFO_FILE) $(post_gen_ip_hook)
	@touch $@


.PHONY: synth_only
## target to run through synthesis only
synth_only: $(DONE_DIR)/synth_only.done

$(DONE_DIR)/synth_only.done: $(DONE_DIR)/synth_ready.done
	$(STP_CHECK)
	@$(BUILD_SCRIPTS)/run_print_err_only.sh \
	   "$O Synthesis (started $(DATE)) $C (see $(BLOG_DIR)/build_synth.log)" \
	   "$(VIVADO_BATCH) -source $(SYNTH_TCL)" \
	   $(BLOG_DIR)/build_synth.log
	@touch $@




.PHONY: impl
## target to run through Implemenation
impl: $(DONE_DIR)/impl.done

$(DONE_DIR)/impl.done: $(DONE_DIR)/synth_only.done $(IMPL_TCL) $(XDC_FILES)
	@$(BUILD_SCRIPTS)/run_print_err_only.sh \
		"$O Implementation (started $(DATE)) $C (see $(BLOG_DIR)/build_impl.log)" \
		"$(VIVADO_BATCH) $(SYNTH_DIR)/post_synth.dcp -source $(IMPL_TCL)" \
		$(BLOG_DIR)/build_impl.log
	@touch $@


define do-bitgen =
@$(BUILD_SCRIPTS)/run_print_err_only.sh \
   "$O Building Bit file (started $(DATE)) $C (see $(BLOG_DIR)/build_bit.log)" \
   "$(VIVADO_BATCH) $(SYNTH_DIR)/post_route.dcp -source $(BITGEN_TCL)" \
   $(BLOG_DIR)/build_bit.log
@touch $@
endef

.PHONY: bitgen
## target to run through Bitstream generation
bitgen: $(DONE_DIR)/bitgen.done
$(DONE_DIR)/bitgen.done: $(DONE_DIR)/impl.done $(BITGEN_TCL)
	$(do-bitgen)

define do-timing =
echo "TODO: do timing analysis"
@touch $@
endef


.PHONY: timing
## target to run through Vivado timing (no bitgen)
timing: $(DONE_DIR)/timing.done
$(DONE_DIR)/timing.done: $(DONE_DIR)/impl.done
	$(do-timing)

# This prevents timing and assembler from running in parallel for synth target
$(DONE_DIR)/timing_seq.done: $(DONE_DIR)/bitgen.done
	$(do-timing)
	@touch $(DONE_DIR)/timing.done


# Parse and store timing report information
TIMING_RPT_CMD := $(HDL_BUILD_PATH)/intel/timing_report_gen.sh $(BLD_DIR) $(TIMING_RPT_FILE)

.PHONY: gen_timing_rpt
## target to generate TQ_timing_report.txt
gen_timing_rpt: $(TIMING_RPT_FILE)
$(TIMING_RPT_FILE): $(DONE_DIR)/timing.done
	@$(TIMING_RPT_CMD)

$(DONE_DIR)/timing_rpt_seq.done: $(DONE_DIR)/timing_seq.done
	@$(TIMING_RPT_CMD)
	@touch $@

$(DONE_DIR)/timing_timing.done: $(DONE_DIR)/asm_timing.done
	@$(TIMING_RPT_CMD)
	@touch $@

.PHONY: run_timing_rpt
## target to generate TQ_timing_report.txt without checking dependencies
run_timing_rpt: | $(SYNTH_DIR)
	@$(TIMING_RPT_CMD)


.PHONY: synth
## target to run full synthesis: synth impl bitgen timing
synth: $(DONE_DIR)/synth.done
$(DONE_DIR)/synth.done: $(DONE_DIR)/timing_seq.done
	@touch $@


ifndef ARCHIVE_DIR
## archive base location, default is `$(BLD_DIR)/archive`
  ARCHIVE_DIR := $(BLD_DIR)/archive
endif
# to eval `date` shell at start, use 'ifndef' combined with ':=' assignment
ifndef ARCHIVE_SUB_DIR
 ifdef GIT_REPO
## archive subdirectory location, default is `build_YYYY_MM_DD-HH.MM-gitbranch`
  ARCHIVE_SUB_DIR := build_$(shell date +"%Y_%m_%d-%H.%M")-$(shell git rev-parse --abbrev-ref HEAD 2> /dev/null || echo nogit)
 else
  ARCHIVE_SUB_DIR := build_$(shell date +"%Y_%m_%d-%H.%M")
 endif
endif
ifndef ARCHIVE_FILE_PREFIX
## prefix archive files, default is `archive_`
  ARCHIVE_FILE_PREFIX := archive_
endif
ifndef ARCHIVE_DEST
## path archive files will be copied. Default is `$(ARCHIVE_DIR)/$(ARCHIVE_SUB_DIR)`
  ARCHIVE_DEST := $(ARCHIVE_DIR)/$(ARCHIVE_SUB_DIR)
endif

define do-archive =
@echo;echo -e "$O Archiving synthesis results to $(ARCHIVE_DEST) $C"
@mkdir -p $(ARCHIVE_DEST)
@-chmod 777 $(ARCHIVE_DEST)
cp $(PROJECT).bit $(ARCHIVE_DEST)/$(ARCHIVE_FILE_PREFIX)$(TOP_SYNTH).bit
cp $(PROJECT).ltx $(ARCHIVE_DEST)/$(ARCHIVE_FILE_PREFIX)$(notdir $(STP_FILE)) || true; \
mkdir -p $(ARCHIVE_DEST)/$(ARCHIVE_FILE_PREFIX)reports
@cp $(SYNTH_DIR)/*.rpt $(ARCHIVE_DEST)/$(ARCHIVE_FILE_PREFIX)reports/ || true
@-cp $(GIT_INFO_FILE) $(ARCHIVE_DEST)/$(ARCHIVE_FILE_PREFIX)git_info.txt
@env > $(ARCHIVE_DEST)/$(ARCHIVE_FILE_PREFIX)env.txt
@-chmod 777 $(ARCHIVE_DEST) -R
endef

# This target will archive whatever is there without checking dependencies
.PHONY: archive_synth_results
## target to archive synthesis results to `ARCHIVE_DEST`
archive_synth_results:
	$(do-archive)

.PHONY: synth_archive
## target to run full synthesis and archive when done
synth_archive: $(DONE_DIR)/timing_rpt_seq.done
	$(do-archive)

.PHONY: clean
clean: clean_vivado
.PHONY: clean_vivado
clean_vivado:
	@rm -rf $(SYNTH_DIR) $(TCL_DIR) $(IP_DIR)

.PHONY: cleanall
cleanall: cleanall_vivado
.PHONY: cleanall_vivado
cleanall_vivado:
	@rm -rf $(SYNTH_DIR)*

##### Extra targets
.PHONY: timing_rpt
## target to print timing report
timing_rpt: $(TIMING_RPT_FILE)
	-@cat $(TIMING_RPT_FILE)
## target to print timing report after repeating fit until timing is met
timing_rpt_timing: $(DONE_DIR)/timing_timing.done
	-@cat $(TIMING_RPT_FILE)
