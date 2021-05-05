#-*- makefile -*-
## ------------------- #
#  Quartus build rules #

ifndef TOP_SYNTH
  ifdef TOP
## identify the top module to be simulated with `TOP_SYNTH`. If not set, `TOP` will be used.
    TOP_SYNTH := $(TOP)
  endif
endif

## identify the FPGA product family, like "Stratix 10" or "Agilex". Should match Quartus string in project settings
# FAMILY: set in upper Makefile
## identify the FPGA device part number, should match Quartus string in project settings
# DEVICE: set in upper Makefile

ifndef NUM_TIMING_TRIES
## tell synth_timing number of tries before giving up on timing
  NUM_TIMING_TRIES := 10
endif

presynth_hook := $(DONE_DIR)/presynth_hook.done
## target hook to run before any synth work
$(presynth_hook): | $(DONE_DIR)
	@touch $@

post_qgen_ip_hook := $(DONE_DIR)/post_qgen_ip_hook.done
## target hook to run after ip generation is done, before mapping
$(post_qgen_ip_hook): $(DONE_DIR)/qgen_ip.done | $(DONE_DIR)
	@touch $@

SYNTH_SUB_DONE := $(DONE_DIR)/synth_substitutions.done

# To print variables that need full dependency includes
.PHONY: printquartus-%
## use `make printquartus-VAR_NAME` to print variable after Quartus processing
printquartus-%:
	@echo '$* = $($*)'

## synthesis enforces `SYNTH_TOOL` version match against tool on `PATH`. Run make with `SYNTH_OVERRIDE=1` to ignore the check.
# SYNTH_OVERRIDE: set in upper Makefile

# Recipe to always run
.PHONY: always_run
always_run:
	@ if [[ "$(SYNTH_OVERRIDE)" != "y" ]]; then \
	    if [[ `which quartus_sh` != *"$(SYNTH_TOOL)"* ]]; then \
	      echo -e "ERROR: $(RED)Missing quartus tool $(SYNTH_TOOL) from path$(NC)\n (prefix with SYNTH_OVERRIDE=y to override)"; false; \
	fi; fi
	@ $(HDL_BUILD_PATH)/intel/quartus_running.sh


SYNTH_DIR := $(BLD_DIR)/$(TOP_SYNTH)
PROJECT := $(SYNTH_DIR)/$(TOP_SYNTH)
IP_DIR := $(CURDIR)/$(BLD_DIR)/ip_cores
IP_MK := $(IP_DIR)/ip.mk
TCL_DIR := $(BLD_DIR)/tcl
FILES_TCL := $(TCL_DIR)/include_files.tcl
PARAMETER_TCL := $(TCL_DIR)/parameters.tcl
EXTRA_TCL := $(DONE_DIR)/extra.tcl
PROJ_TCL := $(TCL_DIR)/project.tcl
GIT_INFO_FILE := $(SYNTH_DIR)/git_info.txt
PRO_RESULT := $(DONE_DIR)/pro_result
QSF_DONE := $(DONE_DIR)/qsf.done
STD_V_PRO_MACRO_FILE := $(TCL_DIR)/std_v_pro_macro.tcl
TIMING_RPT_FILE := $(SYNTH_DIR)/TQ_timing_report.txt
DATE := `date \"+%a %H:%M:%S\"`


##################### Module dependency targets ##############################

MAKEDEP_TOOL_QUARTUS := "quartus"

## a space delineated list of either `module:filename` mappings, or paths to a yaml file defining mappings. If a mapping is blank, dependency matching for the module is blocked. See `examples/example-subs.yml`. For example: `SYNTH_SUBSTITUTIONS = $(shell git_root_path mocks/s10_mocks.yml) eth_100g:$(shell git_root_path mocks/100g_core.ip simonly_check:`
# SYNTH_SUBSTITUTIONS: set in upper Makefile
ifdef SYNTH_SUBSTITUTIONS
  SUBS_QUARTUS := --subsfilelist '$(SYNTH_SUBSTITUTIONS)'
endif

# The .d (dependent) targets are to calculate the dependencies of a file
# The .d recipe is run whenever the sv file changes
# The sv dependency is added in the .d file itself
# The '%' becomes the module name
# The '$*' is replaced by that module name
$(DEP_DIR)/%.quartus.d: $(SYNTH_SUB_DONE) $(predependency_hook) | $(DEP_DIR) $(BLOG_DIR)
	@if [ -d $(SRC_BASE_DIR) ]; then\
	  $(BUILD_SCRIPTS)/run_full_log_on_err.sh  \
	   "Identifying dependencies for $*$(UPDATE)" \
	   "$(MAKEDEPEND_CMD) $(SUBS_QUARTUS) $(MAKEDEP_TOOL_QUARTUS) $*" \
	   $(BLOG_DIR)/dependency_$*_quartus.log; \
	else \
	  echo -e "$(RED)Could not find SRC_BASE_DIR$(NC)"; false; \
	fi


##################### Include top level ##############################

# targets: grep lines that have ':', remove exceptions, sed drop last character
# Extract all targets for synthesis that need dependency analysis:
QUARTUS_TARGETS := $(shell grep -oe "^[a-z].*:" $(HDL_BUILD_PATH)/intel/quartus.mk | grep -v clean | grep -v nuke | grep -v archive_synth_results | sed 's/:.*//')

# When the top .d file is included, make can't do anything until built.
# Make sure it's included only when needed to avoid doing extra work
SYNTH_DEPS := $(filter $(QUARTUS_TARGETS),$(MAKECMDGOALS))
ifneq (,$(SYNTH_DEPS))
  # The top .d file must be called out specifically to get the ball rolling
  # Otherwise nothing happens because there are no matches to the wildcard rule
  ifndef TOP_SYNTH
    $(error No TOP_SYNTH module defined)
  endif
  ifdef	TOP_SYNTH
    -include $(DEP_DIR)/$(TOP_SYNTH).quartus.d
    -include $(IP_MK)
    $(BLD_DIR): always_run
  endif
endif


##################### Synthesis Parameters ##############################
SYNTH_TOP_DEPS := $(sort $(strip $($(TOP_SYNTH)_DEPS)))

# Extra sources for TCL commands
TIMEQUEST_RPT_GEN := $(HDL_BUILD_PATH)/intel/synth_timequest_rpt_gen.tcl

# Altera tool version
# (use `quartus_sh -v | grep -o "Pro"` to avoid path dep, but takes too long)
PRO_VERSION := $(shell which quartus_map 2> /dev/null | grep -o pro || true)

ifeq ($(PRO_VERSION),pro)
  QGEN_IP := quartus_ipgenerate
  IPGEN_ARGS := $(PROJECT) --generate_ip_file --synthesis=VERILOG --ip_file=
else
  space :=
  space +=
  QGEN_IP := qsys-generate
  # Needs whitespace at the end because pro version can't have space when used
  IPGEN_ARGS := --synthesis=VERILOG --part=$(DEVICE) $(space)
  QMW := qmegawiz
  ## TODO: this should be moved to individual makefiles that need it
  QSYS_IP_SEARCH_PARAM := --search-path=${SRC_BASE_DIR}/ip_cores/i2c_opencores,\\$$$$\\$$$$
endif

QSH := quartus_sh

ifeq ($(PRO_VERSION),pro)
  QMAP := quartus_syn
else
  QMAP := quartus_map
endif
MAP_ARGS := --read_settings_files=on --write_settings_files=off

QPART := quartus_cdb
QPART_ARGS := --read_settings_files=on --write_settings_files=off --merge=on

QSTP := quartus_stp
STP_ARGS := --enable --signaltap --stp_file="$(STP_FILE)"
ifdef STP_FILE
  STP_CHECK := @if [ -f "$(STP_FILE)" ]; then \
     $(BUILD_SCRIPTS)/run_print_err_only.sh \
	 "$O Adding SignalTap file to project $C (see $(BLOG_DIR)/build_signaltap.log)" \
	   "cd $(SYNTH_DIR) && $(QSTP) $(TOP_SYNTH) $(STP_ARGS)" \
	   $(BLOG_DIR)/build_signaltap.log; \
 fi;
else
  STP_CHECK :=
endif

QFIT := quartus_fit
FIT_ARGS := --part=$(DEVICE) --read_settings_files=on --write_settings_files=off

QASM := quartus_asm
ASM_ARGS :=

QSTA := quartus_sta
STA_ARGS :=

## file path to a tcl file for Quartus settings that will be included in the QSF
# QUARTUS_FILE: set in upper Makefile
## file path to a tcl file for transciever settings that will be included in the QSF
# XCVR_SETTINGS: set in upper Makefile
## file path to an SDC timing constraints file that will be used in the QSF
# SDC_FILE: set in upper Makefile
## a variable string that will be included directly in QSF
# QSF_EXTRA: set in upper Makefile
ABSPATH_QUARTUS_FILE := $(realpath $(QUARTUS_FILE))
ABSPATH_XCVR_SETTINGS := $(realpath $(XCVR_SETTINGS))
ABSPATH_SDC_FILE := $(realpath $(SDC_FILE))
SDC_DONE := $(DONE_DIR)/sdc.done

##################### Directory targets ##############################
$(SYNTH_DIR): | $(BLD_DIR)
	@mkdir -p $(SYNTH_DIR)

$(IP_DIR): | $(BLD_DIR)
	@mkdir -p $(IP_DIR)

$(TCL_DIR): | $(BLD_DIR)
	@mkdir -p $(TCL_DIR)

$(EXTRA_TCL): $(QUARTUS_FILE) $(XCVR_SETTINGS) | $(DONE_DIR)
	@echo;echo -e "$O Building TCL file to create QSF $C"
	@touch $(EXTRA_TCL)


##################### Dependency targets ##############################
# Create rules to determine dependencies and create compile recipes for .sv
.PHONY: filelist_synth
## print list of files used in synth
filelist_synth: $(DEP_DIR)/$(TOP_SYNTH).quartus.d
	@grep "\.d:" $(DEP_DIR)/* | cut -d " " -f 2 | sort | uniq
.PHONY: modules_synth
## print list of modules used in synth
modules_synth: $(DEP_DIR)/$(TOP_SYNTH).quartus.d
	@echo $(SYNTH_TOP_DEPS)

## track whether Quartus Pro or Std is being used. If Std, sets `VERILOG_MACRO STD_QUARTUS=1`. Always sets `VERILOG_MACRO SYNTHESIS=1`
# PRO_RESULT:
# Check to see whether it's Quartus Pro or Std and record result
ifeq ($(shell $(BUILD_SCRIPTS)/variable_change.sh "$(PRO_VERSION)" $(PRO_RESULT)),yes)
PRO_DEP:=$(PRO_RESULT).tmp
endif

$(PRO_RESULT).tmp: | $(DONE_DIR)
	@echo "$(PRO_VERSION)" > $@
	@if [ ! -f $(PRO_RESULT) ]; then echo; echo "Recording Quartus variation" && cp $@ $(PRO_RESULT); fi
$(PRO_RESULT): $(PRO_DEP) | $(DONE_DIR)
	@-diff $@.tmp $@ >/dev/null 2>&1 \
	    && rm $@.tmp \
	    || (echo "Updating Quartus variation " && mv $@.tmp $@);
	@touch $@

$(STD_V_PRO_MACRO_FILE): $(PRO_RESULT) | $(TCL_DIR)
ifeq ($(PRO_VERSION),pro)
	@echo "" > $@
else
	@echo "set_global_assignment -name VERILOG_MACRO STD_QUARTUS=1" > $@
endif

# the .o files will write to individual files, so cat together into one file
$(FILES_TCL): $(SYNTH_SUB_DONE) $(presynth_hook) $(DEP_DIR)/$(TOP_SYNTH).quartus.o | $(DEP_DIR) $(TCL_DIR)
	@cat $(FILES_TCL).* > $@
	@touch $@

##### Parameters ##
## monitors variables prefixed with **`PARAM_`** and passes them to Quartus. `PARAM_NUM_PORTS := 2` passes a parameter named NUM_PORTS with value of 2.
# PARAM_*: set in upper Makefile

# Gather all PARAM_ environment variables and make a parameter string
# First filter all variables to find all that start with PARAM_
MAKE_PARAMS := $(filter PARAM_%,$(.VARIABLES))
# Next change them from PARAM_NAME to NAME and grab their values
# Output for PARAM_NAME=value: set_parameter -name NAME value;
TCL_PARAM := $(foreach pname, $(MAKE_PARAMS),set_parameter -name $(subst PARAM_,,$(pname)) $($(pname));)
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

# Compare against old results, and force update if different
ifeq ($(shell $(BUILD_SCRIPTS)/variable_change.sh "$(ABSPATH_SDC_FILE)" $(SDC_DONE)),yes)
SDC_DEP=$(SDC_DONE).tmp
endif
# Update the parameters if any of the PARAM_ variable change
$(SDC_DONE).tmp: | $(DONE_DIR)
	@echo "$(ABSPATH_SDC_FILE)" > $@
	@if [ ! -f $(SDC_DONE) ]; then echo; echo "Recording SDC_FILE" && cp $@ $(SDC_DONE); fi
$(SDC_DONE): $(SDC_DEP) $(PRO_RESULT)
	@if [ ! -f $@.tmp ]; then echo "$(ABSPATH_SDC_FILE)" > $@.tmp; fi
	@-diff $@.tmp $@ >/dev/null 2>&1 \
	    && rm $@.tmp \
	    || (echo; echo "Updating SDC_FILE" && mv $@.tmp $@);
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
	    || (echo "Updating SYNTH_SUBSTITUTIONS" && mv $@.tmp $@ && rm $(DEP_DIR)/*.quartus.o);
	@touch $@


# The .o (out) rules are to mark that the file has been compiled
# The .o recipe is used to compile all files
# The source file dependency is added in the .d file
# The "$*" is replaced with the stem, which is the module name
# The "$(word 2,$^)" is the second dependency, which will be the sv filename
# ftype is the filename suffix with out the leading '.'
# ipsearch needs to be set only if it's a qsys type file
# TODO: The `if fpath` below is to quiet a false try cause by including $(IP_MK)
#   For some reason this recipe is called before the files are written
#   This shouldn't be needed -- figure out how to prevent it and remove `if`

# synth_commands.mk includes all the commands run below
# fpath, ftype, fdir, and ipsearch are used in synth_commands.mk
include $(HDL_BUILD_PATH)/intel/synth_commands.mk
COMP_MSG = $(CLEAR)Adding $*$(UPDATE)
SVH_MSG = $(CLEAR)Including directory for $*$(UPDATE)
$(DEP_DIR)/%.quartus.o:  $(PRO_RESULT) | $(DEP_DIR) $(BLOG_DIR) $(IP_DIR) $(TCL_DIR)
	$(eval fpath = $(word 2,$^))
	$(eval ftype = $(subst .,,$(suffix $(word 2,$^))))
	$(eval fdir = $(dir $(fpath)))
	$(if $(filter qsys,$(ftype)),$(eval ipsearch := ${QSYS_IP_SEARCH_PARAM}),)
	@set -e; if [ "$(fpath)" ]; then\
	  if [ ! -f $(DEP_DIR)/$*.quartus.d ]; then \
	    echo -e "$(RED)Dependency .d file missing for $*$(NC), missing source file?"; false;\
	  fi; \
	  if  [[ "$(fpath)" == *.svh || "$(fpath)" == *.vh ]]; then \
	      $(HDL_BUILD_PATH)/intel/run_quartus.sh '$(SVH_MSG)' '$(svh_cmd)' '$(BLOG_DIR)/svh_quartus_$*.log'; \
	  else if [[ "$(fpath)" == *_qmw.v ]]; then \
	      $(HDL_BUILD_PATH)/intel/run_quartus.sh '$(COMP_MSG)' '$(qmegawiz_cmd)' '$(BLOG_DIR)/qmegawiz_$*.log'; \
	  else if [[ "$(fpath)" == *.sv || "$(fpath)" == *.v ]]; then \
	      $(HDL_BUILD_PATH)/intel/run_quartus.sh '$(COMP_MSG)' '$(sv_cmd)' '$(BLOG_DIR)/vlog_quartus_$*.log'; \
	  else if [[ "$(fpath)" == *.ip ]]; then \
	      $(HDL_BUILD_PATH)/intel/run_quartus.sh '$(COMP_MSG)' '$(ip_cmd)' '$(BLOG_DIR)/ip_$*.log'; \
	  else if [[ "$(fpath)" == *.qsys ]]; then \
	      $(HDL_BUILD_PATH)/intel/run_quartus.sh '$(COMP_MSG)' '$(qsys_cmd)' '$(BLOG_DIR)/qsys_$*.log'; \
	  else echo "Unknown filetype: $(fpath)"; echo "$^"; exit 1; fi; fi; fi; fi; fi; \
	  touch $@; \
	else false; fi


##################### Project targets ##############################
# Create rules to create inputs to project QSF file

## all QSF files get the values set in `synth_tcl.mk` global settings, including jtag.sdc
# synth_tcl.mk:

# SDC files MUST be listed after IP files to work in Pro
include $(HDL_BUILD_PATH)/intel/synth_tcl.mk
$(PROJ_TCL): $(FILES_TCL) $(PARAMETER_TCL) $(STD_V_PRO_MACRO_FILE) $(EXTRA_TCL) $(SDC_DONE) | $(TCL_DIR)
	@echo; echo -e "$O Quartus project $C"
	@echo -e "$(synth_global)" > $@
	@cat $(STD_V_PRO_MACRO_FILE) $(FILES_TCL) $(PARAMETER_TCL) >> $@
	@echo -e "$(synth_sdc)" >> $@
	@echo '$(QSF_EXTRA)' >> $@
# Only one IP_SEARCH_PATHS allowed, combine lines with ';'
	@grep IP_SEARCH_PATHS $(PROJ_TCL) | cut -d " " -f4 | sort | uniq | tr '\n' ';' > $(PROJ_TCL).ip
	@if [ -s $(PROJ_TCL).ip ]; then \
	    printf 'set_global_assignment -name IP_SEARCH_PATHS "%b"' "$$(cat $(PROJ_TCL).ip)" >> $(PROJ_TCL); \
	fi


.PHONY: project
## target to create Quartus project
project: $(QSF_DONE)

# Quartus updates the QSF file, so use DONE file for make dependencies
$(QSF_DONE): $(PROJ_TCL) $(GIT_INFO_FILE) | $(SYNTH_DIR) $(DONE_DIR)
	@-rm -f $(PROJECT).qpf $(PROJECT).qsf
	@$(BUILD_SCRIPTS)/run_print_warn_and_err.sh \
	 "Generating Quartus project files" \
	"$(QSH) -t $(PROJ_TCL)" $(BLOG_DIR)/build_qsf.log
	@touch $@


.PHONY: quartus
## target to open Quartus GUI
quartus: $(DONE_DIR)/synth_ready.done
	$(STP_CHECK)
	quartus $(PROJECT).qpf &

.PHONY: quartus_fast
## target to open Quartus GUI without waiting for ip generation
quartus_fast: $(QSF_DONE)
	$(STP_CHECK)
	quartus $(PROJECT).qpf &


# Log relevant repo information before building
$(DONE_DIR)/git.rpt: $(PROJ_TCL) | $(DONE_DIR)
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
$(IP_MK): $(QSF_DONE)
	@if ls $@.* >/dev/null 2>&1; then cat $@.* > $@; fi
	@touch $@

.PHONY: ipgen
## target to generate Quartus IP
ipgen: $(DONE_DIR)/qgen_ip.done | $(DONE_DIR)
# IP rules are built up in $(IP_MK)
$(DONE_DIR)/qgen_ip.done: $(IP_MK)
	@touch $@


$(DONE_DIR)/synth_ready.done: $(DONE_DIR)/qgen_ip.done $(post_qgen_ip_hook)
	@touch $@


.PHONY: elab_synth
## target to run through Quartus analysis and elaboration
elab_synth: $(DONE_DIR)/elab_synth.done
$(DONE_DIR)/elab_synth.done: $(DONE_DIR)/synth_ready.done
	@$(BUILD_SCRIPTS)/run_print_err_only.sh \
	   "$O Elaborating (started $(DATE)) $C (see $(BLOG_DIR)/build_elaboration.log)" \
	   "$(QMAP) --analysis_and_elaboration $(MAP_ARGS) $(PROJECT)" \
	   $(BLOG_DIR)/build_elaboration.log
	@touch $@


.PHONY: map
## target to run through Quartus synthesis/mapping
map: $(DONE_DIR)/merge.done

$(DONE_DIR)/map.done: $(DONE_DIR)/synth_ready.done
	$(STP_CHECK)
	@$(BUILD_SCRIPTS)/run_print_err_only.sh \
	   "$O Synthesis (started $(DATE)) $C (see $(BLOG_DIR)/build_map.log)" \
	   "$(QMAP) $(MAP_ARGS) $(PROJECT)" \
	   $(BLOG_DIR)/build_map.log
	@touch $@


ifeq ($(PRO_VERSION),pro)
  # No partition merge needed in Pro, but does need ip gen
  $(DONE_DIR)/merge.done: $(DONE_DIR)/map.done
	@touch $@
else
  $(DONE_DIR)/merge.done: $(DONE_DIR)/map.done
	@$(BUILD_SCRIPTS)/run_print_err_only.sh \
	   "$O Partition Merge $C (see $(BLOG_DIR)/build_partition.log)" \
	   "$(QPART) $(QPART_ARGS) $(PROJECT) -c $(TOP_SYNTH)" \
	   $(BLOG_DIR)/build_partition.log
	@touch $@
endif


.PHONY: fit
## target to run through Quartus fit
fit: $(DONE_DIR)/fit.done
$(DONE_DIR)/fit.done: $(DONE_DIR)/merge.done $(ABSPATH_SDC_FILE)
	@$(BUILD_SCRIPTS)/run_print_err_only.sh \
	   "$O Fit (started $(DATE)) $C (see $(BLOG_DIR)/build_fit.log)" \
	   "$(QFIT) $(FIT_ARGS) $(PROJECT)" \
	   $(BLOG_DIR)/build_fit.log
	@touch $@


define do-asm =
@$(BUILD_SCRIPTS)/run_print_err_only.sh \
   "$O Building SOF file (started $(DATE)) $C (see $(BLOG_DIR)/build_asm.log)" \
   "$(QASM) $(ASM_ARGS) $(PROJECT)" \
   $(BLOG_DIR)/build_asm.log
@touch $@
endef

.PHONY: asm
## target to run through Quartus assembler (no timing)
asm: $(DONE_DIR)/asm.done
$(DONE_DIR)/asm.done: $(DONE_DIR)/fit.done
	$(do-asm)

define do-timing =
@$(BUILD_SCRIPTS)/run_print_err_only.sh \
   "$O Analyzing timing (started $(DATE)) $C (see $(BLOG_DIR)/build_sta.log)" \
   "$(QSTA) $(STA_ARGS) $(PROJECT)" \
   $(BLOG_DIR)/build_sta.log
@touch $@
endef

.PHONY: timing
## target to run through Quartus timing (no assembler)
timing: $(DONE_DIR)/timing.done
$(DONE_DIR)/timing.done: $(DONE_DIR)/fit.done $(TIMEQUEST_RPT_GEN)
	$(do-timing)

# This prevents timing and assembler from running in parallel for synth target
$(DONE_DIR)/timing_seq.done: $(DONE_DIR)/asm.done
	$(do-timing)
	@touch $(DONE_DIR)/timing.done


# Parse and store timing report information
TIMING_RPT_CMD := $(HDL_BUILD_PATH)/intel/timing_report_gen.sh $(BLD_DIR) $(TIMING_RPT_FILE)

.PHONY: gen_timing_rpt
gen_timing_rpt: $(TIMING_RPT_FILE)
$(TIMING_RPT_FILE): $(DONE_DIR)/timing.done | $(SYNTH_DIR)
	@$(TIMING_RPT_CMD)

.PHONY: gen_timing_rpt_timing
gen_timing_rpt_timing: $(DONE_DIR)/timing_timing.done
$(DONE_DIR)/timing_timing.done: $(DONE_DIR)/asm_timing.done | $(DONE_DIR) $(SYNTH_DIR)
	@$(TIMING_RPT_CMD)
	@touch $@

.PHONY: run_timing_rpt
## target to generate TQ_timing_report.txt
run_timing_rpt: | $(SYNTH_DIR)
	@$(TIMING_RPT_CMD)


# Path for synth_timing. To specify num tries: override NUM_TIMING_TRIES
.PHONY: fit_timing
## target to run fit until timing is made
fit_timing: $(DONE_DIR)/fit_timing.done
$(DONE_DIR)/fit_timing.done: $(DONE_DIR)/merge.done
	@echo -e "$O Timing Fit, $(NUM_TIMING_TRIES) tries (started $(DATE)) $C"
	@$(HDL_BUILD_PATH)/intel/timing_rerun.py $(SYNTH_DIR) $(PROJECT) $(DONE_DIR)/map.done -n $(NUM_TIMING_TRIES) || (grep --color -i "Error (|Critical Warning (" $(PROJECT).fit.rpt && false)
	@touch $(DONE_DIR)/fit.done
	@touch $(DONE_DIR)/timing.done
	@touch $@

.PHONY: asm_timing
## target to Quartus assembler after running fit until timing is made
asm_timing: $(DONE_DIR)/asm_timing.done
$(DONE_DIR)/asm_timing.done: $(DONE_DIR)/fit_timing.done
	$(do-asm)
	@touch $(DONE_DIR)/asm.done


.PHONY: synth
## target to run full synthesis: map fit asm timing
synth: $(DONE_DIR)/synth
$(DONE_DIR)/synth: $(DONE_DIR)/timing_seq.done
	@touch $@

.PHONY: synth_timing
## target to run full synthesis, running fit until timing is made
synth_timing: $(DONE_DIR)/synth_timing
$(DONE_DIR)/synth_timing: $(DONE_DIR)/timing_timing.done
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
cp $(PROJECT).sof $(ARCHIVE_DEST)/$(ARCHIVE_FILE_PREFIX)$(TOP_SYNTH).sof
@if [ -n "$(STP_FILE)" ]; then \
  cp $(STP_FILE) $(ARCHIVE_DEST)/$(ARCHIVE_FILE_PREFIX)$(notdir $(STP_FILE)) || true; \
fi
-cp $(PROJECT).qsf $(ARCHIVE_DEST)/$(ARCHIVE_FILE_PREFIX)project.qsf
-cp $(PROJECT).fit.summary $(ARCHIVE_DEST)/$(ARCHIVE_FILE_PREFIX)project.fit.summary
mkdir -p $(ARCHIVE_DEST)/$(ARCHIVE_FILE_PREFIX)timequest
@cp $(SYNTH_DIR)/TQ* $(ARCHIVE_DEST)/$(ARCHIVE_FILE_PREFIX)timequest/ || true
cp $(TIMING_RPT_FILE) $(ARCHIVE_DEST)/$(ARCHIVE_FILE_PREFIX)timing_rpt.txt
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
synth_archive: $(DONE_DIR)/synth
	$(do-archive)

.PHONY: synth_archive_timing
## target to run full synthesis, running fit until timing is made, and archive when done
synth_archive_timing: $(DONE_DIR)/synth_timing
	$(do-archive)

.PHONY: clean
clean: clean_quartus
.PHONY: clean_quartus
clean_quartus:
	@rm -rf $(SYNTH_DIR) $(TCL_DIR) $(IP_DIR)

.PHONY: cleanall
cleanall: cleanall_quartus
.PHONY: cleanall_quartus
cleanall_quartus:
	@rm -rf $(SYNTH_DIR)*

##### Extra targets
.PHONY: timing_rpt
## target to print timing report
timing_rpt: $(TIMING_RPT_FILE)
	-@cat $(TIMING_RPT_FILE)
## target to print timing report after repeating fit until timing is met
timing_rpt_timing: $(DONE_DIR)/timing_timing.done
	-@cat $(TIMING_RPT_FILE)

# Search the timing report for error lines and exit error if found
.PHONY: timing_check_all
## target to report timing problems
timing_check_all: $(TIMING_RPT_FILE)
	egrep ':;[^;]*; -[^;]*; [0-9]+.*|Worst-case setup slack is -|Illegal .*[1-9].*|Unconstrained .*[1-9].*|Found combinational loop|Inferred latch' $(TIMING_RPT_FILE) && exit 1
## target to report timing problems after repeating fit until timing is met
timing_check_all_timing: $(DONE_DIR)/timing_timing.done
	egrep ':;[^;]*; -[^;]*; [0-9]+.*|Worst-case setup slack is -|Illegal .*[1-9].*|Unconstrained .*[1-9].*|Found combinational loop|Inferred latch' $(TIMING_RPT_FILE) && exit 1
