#-*- makefile -*-
SYNTH_TOOL := quartuspro_20.4
SW_DIR := $(SRC_BASE_DIR)/../sw
STP_DIR := $(SRC_BASE_DIR)/../stp

PARAM_BUILD_IN_SOC := 1

FAMILY := "Arria 10"
DEVICE := 10AS066N2F40I2SG
# Remove simcheck module from inclusion entirely by mapping to nothing
SYNTH_SUBSTITUTIONS := $(SRC_BASE_DIR)/ip_cores/a10_ip_cores.yml simcheck:

NUM_TIMING_TRIES := 3

ARCHIVE_DIR := /build/archives
ARCHIVE_SUB_DIR := testbuilds/$(shell date +"%Y_%m_%d-%H.%M")-$(shell git rev-parse --abbrev-ref HEAD)
ARCHIVE_FILE_PREFIX := soc_

TOP_SYNTH := soc_top
QUARTUS_FILE := ../soc_make.tcl
SDC_FILE := ../soc.sdc
STP_FILE := $(STP_DIR)/soc.stp

QSF_EXTRA := set_global_assignment -name ENABLE_INIT_DONE_OUTPUT ON

include /path/to/hdl_build/build.mk

# Example to build NIOS software before synthesis
LOCAL_HEX := $(SYNTH_DIR)/nios_debug_instruction_memory.hex
SW_HEX := $(SW_DIR)/src/build/built.hex

.PHONY: check_embedded_pae
$(SW_HEX):
	cd $(SW_DIR)/src/build && ./build_sw.sh

$(LOCAL_HEX): $(SW_HEX) | $(SYNTH_DIR)
	cp $(SW_HEX) $@

$(presynth_hook): $(LOCAL_HEX)

# Example for manually generating IP before synthesis
ETH_1G_FILE := $(SRC_BASE_DIR)/ip_cores/ethernet/eth_1g_sgmii_a10.qsys
IP_FILE := $(IP_DIR)/eth_1g_sgmii_a10.qsys
QIP_FILE := $(IP_DIR)/eth_1g_sgmii_a10/eth_1g_sgmii_a10.qip
QIP_DONE := $(DONE_DIR)/eth_17.0.done
QGEN_170 := /opt/quartuspro_17.0.0.290/quartus/sopc_builder/bin/qsys-generate
BUILD_ETH := $(QGEN_170) $(IP_FILE) --synthesis=VERILOG --part=$(DEVICE)

# Generate a makefile for the IP, will be added to IP_MK
$(QIP_DONE): | $(IP_DIR) $(TCL_DIR)
	@echo -e "$O Including custom build rule for 17.0 ethernet mac $C"
	@echo -e "$(QIP_FILE): $(ETH_1G_FILE)\n\
\t@cp $(ETH_1G_FILE) $(IP_FILE)\n\
\t@rm -rf $(IP_DIR)/eth_1g_sgmii_a10\n\
\t@$(SCRIPTS)/run_print_err_only.sh \"Generating 17.0 tse (see $(BLOG_DIR)/qsys_ipgen_tse_17.0.log)\" \"$(BUILD_ETH)\" \"$(BLOG_DIR)/qsys_ipgen_tse_17.0.log\"\n\
\n\
$(DONE_DIR)/qgen_ip.done: $(QIP_FILE)\n\
" > $(IP_MK).eth_17.0
	echo "set_global_assignment -name QIP_FILE $(QIP_FILE)" > $(FILES_TCL).eth_17.0
	@touch $@

$(presynth_hook): $(QIP_DONE)

# Example of running software build after NIOS is generated
POSTGEN_DIR := $(CURDIR)/$(BLD_DIR)/software
SW_BUILD := $(SRC_BASE_DIR)/nios_fpga/do_sw_build.sh
BUILD_POSTGEN := $(SW_BUILD) $(POSTGEN_DIR)
$(SYNTH_DIR)/postgen_nios.hex: \
  $(SRC_BASE_DIR)/nios_fpga/postgen_example.c \
  $(SRC_BASE_DIR)/nios_fpga/postgen_makefile.sh \
  $(IP_DIR)/postgen_nios/postgen_nios.qip
	mkdir -p $(POSTGEN_DIR)
	@$(SCRIPTS)/run_print_err_only.sh \
	  "$O Building postgen software $C (see $(BLOG_DIR)/postgen_compile.log)" \
	  "$(BUILD_POSTGEN)" $(BLOG_DIR)/postgen_compile.log
	cp $(POSTGEN_DIR)/mem_init/postgen_nios_instruction_data.hex $@

$(post_qgen_ip_hook): $(SYNTH_DIR)/postgen_nios.hex
