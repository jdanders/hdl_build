#-*- makefile -*-
SIM_TOOL := questa_10.7

TOP_TB := adder_top
UVM_TEST := sw_fpga_config_test

# mocks
SIM_SUBSTITUTIONS := mock_config_ipcores.yml

# test parameters
UVM_TIMEOUT := 70000000000
PARAM_PERCENT_VALID := 85
PARAM_PERCENT_READY := 85

VSIM_OPTIONS = -optionset UVMDEBUG +UVM_TESTNAME=$(UVM_TEST) +UVM_TIMEOUT=$(UVM_TIMEOUT)

# For examples below: EXTRA_DIRS and SIM_LIB_APPEND must be set before `include`
PY_GEN := $(SRC_BASE_DIR)/python_gen_scripts
GEN_DIR = $(BLD_DIR)/gen
EXTRA_DIRS = $(GEN_DIR)
SIM_LIB_APPEND := -L v3model

include /path/to/hdl_build/build.mk

# Example of compiling an external sim library

MODEL_TIMEOUT_OVERRIDE := +define+MainBlockErase_time=8000 +define+WordProgram_time=850
v3ROOT := $(SRC_BASE_DIR)/ip_cores/flash/micro_stack_2g

$(DONE_DIR)/flash_v3model: $(v3ROOT)/dut/code/28F512.v $(v3ROOT)/dut/stack_2G.v $(v3ROOT)/CFImemory1Gb_top.vmf $(v3ROOT)/memory_0.vmf $(v3ROOT)/memory_1.vmf |$(DONE_DIR) $(SIM_LIB_DIR)
	echo "v3model = $(SIM_LIB_DIR)/v3model" > $(SIM_LIB_DIR)/v3model.map
	vlib $(SIM_LIB_DIR)/v3model
	vlog -work $(SIM_LIB_DIR)/v3model $(VLOG_PARAMS) $(MODEL_TIMEOUT_OVERRIDE) "+incdir+$(v3ROOT)" $(DEFAULT_SIM_LIB) $(v3ROOT)/dut/code/28F512P30.v $(v3ROOT)/dut/stack_2G.v
	cp $(v3ROOT)/CFImemory1Gb_top.vmf .
	cp $(v3ROOT)/memory_0.vmf .
	cp $(v3ROOT)/memory_1.vmf .
	touch $@

$(presimlib_hook): $(DONE_DIR)/flash_v3model

# Example of generating code before dependency analysis
$(GEN_DIR): | $(BLD_DIR)
	mkdir -p $@

$(GEN_DIR)/generated_state.svh: $(PY_GEN)/gen_state.py | $(GEN_DIR)
	@echo -e "$O Generating source files $C"
	python gen_state.py $@

$(predependency_hook): $(GEN_DIR)/generated_state.svh
