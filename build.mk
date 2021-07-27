#-*- makefile -*-
## ---------------- #
#  Core build rules #
# Usage notes:
# * Shell command performance is greatly increased when variables are immediate
#   so all assignments are ':=' variety. Use the 'override' command in upper
#   makefiles if you'd like to change one of these values. For example:
#    override BLOG_DIR := build_logs

# When creating new targets for users, add a ## comment on the line for help
.DEFAULT_GOAL := helpall

# Disable implicit suffixes for performance
MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

## Set `VERBOSE=1` to run fully verbose commands
# VERBOSE: set in upper Makefile or environment

## Set `NOUPDATE=1` to print every line instead of updating
# NOUPDATE: set in upper Makefile or environment

## Set `SLOW=1` to disable parallel building
# SLOW: set in upper Makefile or environment

# Enable parallel processing by default
CPUS ?= $(shell nproc || echo 1)
ifndef SLOW
  MAKEFLAGS += --jobs=$(CPUS)
endif

# Recipes use bash
SHELL = /bin/bash

# SRC_BASE_DIR is the directory to search for source files
HDL_BUILD_PATH := $(abspath $(lastword $(MAKEFILE_LIST))/..)
BUILD_SCRIPTS := $(HDL_BUILD_PATH)/build
include $(BUILD_SCRIPTS)/color.mk

# In git repo?
GIT_ROOT := $(shell $(BUILD_SCRIPTS)/git_root_path)
ifneq (Could not find git root path,$(GIT_ROOT))
## this variable is only defined if the Makefile is in a git repository (test `ifdef GIT_REPO` in makefile to check if in git repo)
  GIT_REPO := $(GIT_ROOT)
endif
# If not a git repo, define SRC_BASE_DIR outside of hdl_build
ifdef GIT_REPO
## directory that holds all relevant source code. Will be assumed to be the current repo if in a git repository.
  SRC_BASE_DIR := $(GIT_ROOT)
endif
# Make SRC_BASE_DIR available to sub commands
export SRC_BASE_DIR


## Default value: `touch .ignore_build_system` in a directory that should be ignored by the build system. Changing this variable will change then name of the file.
IGNORE_FILE := .ignore_build_system


##################### Directory targets ##############################

# BLD_DIR holds all make system results
ifndef BLD_DIR
## directory where build results are stored
  BLD_DIR := bld
endif
export BLD_DIR
$(BLD_DIR):
	@mkdir -p $(BLD_DIR)
	@touch $(BLD_DIR)/$(IGNORE_FILE)

# BLOG (build log) directory holds logs of commands that were quieted
BLOG_DIR := $(BLD_DIR)/buildlogs
$(BLOG_DIR):
	@mkdir -p $(BLOG_DIR)

# DONE directory holds touched files live after build step is done
DONE_DIR := $(BLD_DIR)/done
$(DONE_DIR): | $(BLD_DIR)
	@mkdir -p $(DONE_DIR)

# DEP directory holds the .d (dependency) files
DEP_DIR := $(BLD_DIR)/deps
$(DEP_DIR): | $(BLD_DIR)
	@mkdir -p $(DEP_DIR)

# Use this rule in a Makefile to force a recipe before anaylzing dependencies
predependency_hook := $(DONE_DIR)/predependency_hook.done
## target hook to run something before dependency analysis
$(predependency_hook): | $(DONE_DIR)
	@touch $@

# Helper function to filter strings to their unique members
uniq = $(if $1,$(firstword $1) $(call uniq,$(filter-out $(firstword $1),$1)))


##################### include other build modules ##############################

## select which simulation tool should be used: modelsim, questa or qverify, vivado
# SIM_TOOL: set in defaults.mk, upper Makefile, or environment
-include $(HDL_BUILD_PATH)/defaults.mk

ifdef SIM_TOOL
 ifeq (modelsim,$(findstring modelsim,$(SIM_TOOL)))
  include $(HDL_BUILD_PATH)/siemens/modelsim.mk
 else ifeq (questa,$(findstring questa,$(SIM_TOOL)))
  include $(HDL_BUILD_PATH)/siemens/questa.mk
 else ifeq (qverify,$(findstring qverify,$(SIM_TOOL)))
  include $(HDL_BUILD_PATH)/siemens/questa.mk
 else ifeq (vivado,$(findstring vivado,$(SIM_TOOL)))
  include $(HDL_BUILD_PATH)/xilinx/xsim.mk
 endif
endif

## select which synthesis tool should be used: quartuspro, quartus or vivado
# SYNTH_TOOL: set in defaults.mk
ifdef SYNTH_TOOL
 ifeq (quartus,$(findstring quartus,$(SYNTH_TOOL)))
  include $(HDL_BUILD_PATH)/intel/quartus.mk
 else ifeq (vivado,$(findstring vivado,$(SYNTH_TOOL)))
  include $(HDL_BUILD_PATH)/xilinx/vivado.mk
 endif
endif

# addon make files are not included in hdl_build, but are included in local git
-include $(wildcard $(HDL_BUILD_PATH)/*_addon.mk)
# custom make files are not included in git, customize this repo
-include $(wildcard $(HDL_BUILD_PATH)/*_custom.mk)


##################### Module discovery targets ##############################

## a list of space delineated directory names to ignore during dependency search
# IGNORE_DIRS: set in upper Makefile
ifdef IGNORE_DIRS
  IGNORE_PARAM := --ignoredirs '$(IGNORE_DIRS)'
endif

## a list of space delineated directory names to add during dependency search. This is only useful for directories normally ignored by the build system or a directory outside the `SRC_BASE_DIR` directory.
# EXTRA_DIRS: set in upper Makefile
ifdef EXTRA_DIRS
  EXTRA_PARAM := --extradirs '$(EXTRA_DIRS)'
endif

MAKEDEPEND_CMD := $(BUILD_SCRIPTS)/build_dependency_files.py $(EXTRA_PARAM) --ignorefile $(IGNORE_FILE) $(IGNORE_PARAM) $(SRC_BASE_DIR) $(DEP_DIR)


##################### Cleaning targets ##############################

.PHONY: clean
## target to force redo of build steps and remove previous logs
clean:
	@echo -e "$O Removing build files $C"
	@find $(BLD_DIR) -maxdepth 1 -type f -delete > /dev/null 2>&1 || true
	@rm -rf $(DONE_DIR) $(BLOG_DIR) $(DEP_DIR)

.PHONY: cleanall
## target to remove all build results
cleanall: clean
	@echo;echo -e "$O Removing all build related files $C";echo
	@rm -rf $(BLD_DIR)
	@rm -f *.hex *.dat *.mif

.PHONY: nuke
## target to alias for cleanall
nuke: cleanall


##################### Helper targets ##############################
# List of source makefiles not in the bld directory
SRC_MAKEFILES = $(filter-out $(BLD_DIR)/%,$(MAKEFILE_LIST))

.PHONY: list_targets
## target to list all available Makefile targets
list_targets:
	@$(MAKE) MAKEFLAGS=-r -nqp .DEFAULT | awk -F':' '/^[a-zA-Z0-9][^$$#\/\t=]*:([^=]|$$)/ {split($$1,A,/ /);for(i in A)print A[i]}' | sort -u

.PHONY: print-%
## target to use `make print-VARIABLE_NAME` to examine `VARIABLE_NAME`'s value. For example: `make print-BLD_DIR`
print-%:
	@echo '$* = $($*)'

.PHONY: print-Makefiles
## target to print a list of all included makefiles
print-Makefiles:
	@echo $(MAKEFILE_LIST)

# Help is a line starting with '##' followed by help text
# The next line is the subject of the help followed by ':'
HELP_GREP := grep --no-group-separator -A1 -hE '^\#\# ' $(MAKEFILE_LIST)
.PHONY: help
## target to show brief help.
help:
	@$(HELP_GREP) | sed -e '$!N;s/## \(.*\)\n[# ]*\([^ ]*\) *:.*/\2/'
## target to show this help.
helpall:
	@$(HELP_GREP) | sed -e '$!N;s/## \(.*\)\n[# ]*\([^ ]*\) *:.*/\2:\n  \1/'

helpmarkdown:
	@$(HELP_GREP) | sed -e '$!N;s/## \(.*\)\n[# ]*\([^ ]*\) *:.*/* **`\2`**: \1/' | sed 's/ For example: /\n    * /g'

# Bash auto-complete uses this target, specify to make sure nothing happens
.DEFAULT:
