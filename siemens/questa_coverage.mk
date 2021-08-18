#-*- makefile -*-

COV_VOPT_DONE := $(DONE_DIR)/cov_vopt.done

## Coverage options for `vopt` command (default does not enable toggle coverage)
COV_COVER_OPT := +cover=bcesf
COV_VOPT_PARAMS := $(SUPPRESS_PARAMS) $(MS_INI_PARAM) $(COV_COVER_OPT) $(strip +acc $(VOPT_OPTIONS))

COV_UCDB := $(BLD_DIR)/coverage.ucdb
ifndef COV_MERGED_UCDB
## Location to store result of accumulated coverage report
  COV_MERGED_UCDB := /tmp/coverage_merged_$(USER).ucdb
endif


COV_TEST_TIME := $(shell date +%s.%N)

##################### Dependency targets ##############################
# Create rules to determine dependencies and create compile recipes for .sv

COV_VOPT_CMD := "vopt -sv -work $(SIM_LIB_DIR)/$(SIEMENS_TOP) $(COV_VOPT_PARAMS) $(SIM_LIB_LIST) $(SIM_PARAM) $(SIM_LIB_DIR)/$(SIEMENS_TOP).$(SIEMENS_TOP) -o $(SIEMENS_TOP)_cov_opt"
COV_VOPT_MSG := "$O Optimizing design $C (see $(BLOG_DIR)/vopt_coverage.log)"

$(COV_VOPT_DONE): $(DEP_DIR)/$(SIEMENS_TOP).questa.o $(PARAMETER_DONE) | $(DONE_DIR)
	@$(BUILD_SCRIPTS)/run_print_warn_and_err.sh $(COV_VOPT_MSG) $(COV_VOPT_CMD) $(BLOG_DIR)/vopt_coverage.log
	@touch $(COV_VOPT_DONE)


## Coverage options for `vsim` command
COV_VSIM_OPT := -coverage

## commands to add to batch for coverage
COVERAGE_COMMANDS := coverage report -output $(BLD_DIR)/coverage_report.txt -assert -directive -cvg -codeAll; coverage save -testname $(SIEMENS_TOP).$(COV_TEST_TIME) $(COV_UCDB)

.PHONY: vopt_coverage
## target to perform vopt for coverage after compile
vopt_coverage: comp $(COV_VOPT_DONE)

# The onfinish stop makes sure we can execute commands after run -all
# before the simulator exits.  Without that, if someone used a $finish
# at the end of their simulation the simulator would exit right after
# run -all and skip any commands that come after that.
COV_BATCH_OPTIONS := -batch -do "onfinish stop; run -all; $(COVERAGE_COMMANDS); exit"

# Top level name for sim, used in do_coverage_files.mk
COV_COMP := $(SIEMENS_TOP)_cov_opt

include $(HDL_BUILD_PATH)/siemens/do_files.mk
include $(HDL_BUILD_PATH)/siemens/do_coverage_files.mk

# Build dependencies for do script variable
# Compare against old results, and force update if different
# This is different than normal sim because batch_accumulate_coverage does not
# force a rerun of the `vsim` command like normal sim or batch targets do
COV_DO_DONE := $(DONE_DIR)/cov_do.done
# test string includes a time stamp, which would break this. Remove time stamp.
COV_DO_STR := $(subst $(COV_TEST_TIME),,"$(sim_coverage_str) $(elab_coverage_str) $(batch_coverage_str)")
ifeq ($(shell $(BUILD_SCRIPTS)/variable_change.sh $(COV_DO_STR) $(COV_DO_DONE)),yes)
COV_DO_DEP=$(COV_DO_DONE).tmp
endif

# Update the substitutions if the COV_DO variable changes
$(COV_DO_DONE).tmp: | $(DONE_DIR)
	@echo  $(COV_DO_STR) > $@
	@if [ ! -f $(COV_DO_DONE) ]; then echo "Recording vsim do command" && cp $@ $(COV_DO_DONE); fi
$(COV_DO_DONE): $(COV_DO_DEP)
	@-diff $@.tmp $@ >/dev/null 2>&1 \
	    && rm $@.tmp \
	    || (echo "Updating vsim do command" && mv $@.tmp $@);
	@touch $@

.PHONY: sim_coverage
# to run make commands cleanly in GUI, remove -j flags
## target to run simulation in GUI with coverage
sim_coverage: $(PARAMETER_DONE) $(COV_DO_DONE) $(COV_VOPT_DONE) $(presim_hook)
	@echo -e "$(sim_coverage_str)" > $(SIM_SCRIPT)
	@echo -e '$(restart_str)' > $(RESTART_SCRIPT)
	@echo -e '$(resim_str)' > $(RESIM_SCRIPT)
	@echo -e "$O Starting simulation $C"
	MAKEFLAGS="-r" vsim $(MS_INI_PARAM) -i -do $(SIM_SCRIPT)&


.PHONY: elab_coverage
## target to run elaboration batch for coverage
elab_coverage: $(PARAMETER_DONE) $(COV_DO_DONE) $(COV_VOPT_DONE) $(presim_hook)
	@echo -e "$(elab_coverage_str)" > $(BATCH_SCRIPT)
	@chmod +x $(BATCH_SCRIPT)
	@echo -e "$O Starting batch simulation $C (see $(BLOG_DIR)/batch.log)"
	@$(HDL_BUILD_PATH)/siemens/run_siemens.sh "./$(BATCH_SCRIPT)" \
	 "./$(BATCH_SCRIPT)" "$(BLOG_DIR)/batch.log"


.PHONY: batch_coverage
## target to run simulation batch with coverage
batch_coverage: $(COV_UCDB)
$(COV_UCDB): $(PARAMETER_DONE) $(COV_DO_DONE) $(COV_VOPT_DONE) $(presim_hook)
	@echo -e "$(batch_coverage_str)" > $(BATCH_SCRIPT)
	@chmod +x $(BATCH_SCRIPT)
	@echo -e "$O Starting batch simulation $C (see $(BLOG_DIR)/batch.log)"
	@if $(HDL_BUILD_PATH)/siemens/run_siemens.sh "./$(BATCH_SCRIPT)" \
	    "./$(BATCH_SCRIPT)" "$(BLOG_DIR)/batch.log" ; then \
	     echo -e "$(GREEN)# Simulation successful $C"; \
	 else false; fi


# To be run in a `for` loop on variable named submod
# Downgrade vcover-6821 to note: Object type mismatch detected while merging
COV_ADD_MERGE_CMD := vcover merge -note 6821 -du $${submod} $(COV_UCDB).$${submod} $(COV_UCDB) && vcover merge -note 6821 $(COV_MERGED_UCDB) $(COV_MERGED_UCDB) $(COV_UCDB).$${submod}


# Coverage accumulation extracts coverage for each submodule included
# in the sim and adding that coverage to the combined coverage ucdb file.
# The resulting $(COV_MERGED_UCDB) ucdb has individual entries per submodule.
.PHONY: batch_accumulate_coverage
## target to run simulation batch with accumulated coverage
batch_accumulate_coverage: $(COV_UCDB)
	@echo -e "$O Accumulting coverage $C"
	@for submod in $(SIM_TOP_DEPS); do\
	  $(HDL_BUILD_PATH)/siemens/run_siemens.sh \
	    "Adding coverage for $${submod} to $(COV_MERGED_UCDB)" \
	    "$(COV_ADD_MERGE_CMD)" "$(BLOG_DIR)/cov_add_$${submod}.log";true;\
	done


.PHONY: coverage_view
## target to view coverage
coverage_view:
	vsim -gui -viewcov $(COV_UCDB) &

.PHONY: coverage_view_all
## target to view accumulated coverage
coverage_view_all:
	vsim -gui -viewcov $(COV_MERGED_UCDB) &

.PHONY: clean
clean: clean_questa_coverage
.PHONY: clean_questa_coverage
clean_questa_coverage:
	@rm -rf $(BLD_DIR)/coverstore

.PHONY: nuke
nuke: clean_cover_db
.PHONY: clean_cover_db
## target to remove accumulated coverage ucdb file
clean_cover_db:
	@rm -f $(COV_MERGED_UCDB)
