#-*- makefile -*-
#--- Core build rules: ## ----------------
# Usage notes:
# * Shell command performance is greatly increased when variables are immediate
#   so all assignments are ':=' variety. Use the 'override' command in upper
#   makefiles if you'd like to change one of these values. For example:
#    override BLD_DIR := bld_test

# When creating new targets for users, add a ## comment on the line for help
.DEFAULT_GOAL := helpall

# Disable implicit suffixes for performance
MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

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
  GIT_REPO := $(GIT_ROOT)
endif
# If not a git repo, define SRC_BASE_DIR outside of hdl_build
ifdef GIT_REPO
  SRC_BASE_DIR := $(GIT_ROOT)
endif

# set IGNORE_DIRS in upper makefile
# `touch .ignore_build_system` in a directory that should be ignored
IGNORE_FILE := .ignore_build_system


##################### Directory targets ##############################

# BLD_DIR holds all make system results
BLD_DIR := bld
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
$(predependency_hook): | $(DONE_DIR) ## hook to run before dependency
	@touch $@

# Helper function to filter strings to their unique members
uniq = $(if $1,$(firstword $1) $(call uniq,$(filter-out $(firstword $1),$1)))


##################### include other build modules ##############################

-include $(HDL_BUILD_PATH)/default_sim.mk
-include $(HDL_BUILD_PATH)/default_synth.mk

ifdef SIM_TOOL
 ifeq (modelsim,$(findstring modelsim,$(SIM_TOOL)))
  include $(HDL_BUILD_PATH)/siemens/modelsim.mk
 else ifeq (questa,$(findstring questa,$(SIM_TOOL)))
  include $(HDL_BUILD_PATH)/siemens/questa.mk
 endif
endif

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

ifdef IGNORE_DIRS
  IGNORE_PARAM := --ignoredirs '$(IGNORE_DIRS)'
endif

ifdef EXTRA_DIRS
  EXTRA_PARAM := --extradirs '$(EXTRA_DIRS)'
endif

MAKEDEPEND_CMD := $(BUILD_SCRIPTS)/build_dependency_files.py $(EXTRA_PARAM) --ignorefile $(IGNORE_FILE) $(IGNORE_PARAM) $(SRC_BASE_DIR) $(DEP_DIR)


##################### Cleaning targets ##############################

.PHONY: clean
clean: ## force redo of dependency analysis and beyond
	@echo -e "$O Removing build files $C"
	@find $(BLD_DIR) -maxdepth 1 -type f -delete > /dev/null 2>&1 || true
	@rm -rf $(DONE_DIR) $(BLOG_DIR) $(DEP_DIR)

.PHONY: cleanall
cleanall: clean ## remove all build results
	@echo;echo -e "$O Removing all build related files $C";echo
	@rm -rf $(BLD_DIR)
	@rm -f *.hex *.dat *.mif

.PHONY: nuke
nuke: cleanall ## alias for cleanall


##################### Helper targets ##############################
# List of source makefiles not in the bld directory
SRC_MAKEFILES = $(filter-out $(BLD_DIR)/%,$(MAKEFILE_LIST))

# A target that lists all targets.
.PHONY: list_targets
list_targets: ## list all available targets
	@$(MAKE) MAKEFLAGS= -nqp .DEFAULT | awk -F':' '/^[a-zA-Z0-9][^$$#\/\t=]*:([^=]|$$)/ {split($$1,A,/ /);for(i in A)print A[i]}' | sort -u

# print the value of any variable.  Just type:
# make print-VARIABLE_NAME
#
# Got this magic from here: https://blog.melski.net/2010/11/30/makefile-hacks-print-the-value-of-any-variable/
.PHONY: print-%
print-%: ## use 'make print-VAR_NAME' to examine variable values
	@echo '$* = $($*)'

.PHONY: print-Makefiles
print-Makefiles: ## print a list of all included makefiles
	@echo $(MAKEFILE_LIST)

.PHONY: help
help:           ## Show brief help.
	@echo -e "$$(grep -hE ':.*##' $(MAKEFILE_LIST) | grep -v grep | sed -e 's/\\$$//' | sed -e 's/:.*##.*//')"
helpall:           ## Show this help.
	@echo -e "$$(grep -hE ':.*##' $(MAKEFILE_LIST) | grep -v grep | sed -e 's/\\$$//' | sed -e 's/:.*##/:\n  /')"

# Bash auto-complete uses this target, specify to make sure nothing happens
.DEFAULT:
