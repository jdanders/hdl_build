# This is needed for subst command below
define newline


endef


define sim_coverage
vsim -i $(VSIM_PARAMS) $(COV_VSIM_OPT) $(SIM_LIB_LIST) -sv_seed $(SIM_SEED) $(SIM_LIB_DIR)/$(SIEMENS_TOP).$(COV_COMP)

endef


define batch_coverage
#!/bin/bash

vsim $(VSIM_PARAMS) $(COV_VSIM_OPT) $(SIM_LIB_LIST) -sv_seed $(SIM_SEED) $(COV_BATCH_OPTIONS) $(SIM_LIB_DIR)/$(SIEMENS_TOP).$(COV_COMP)

endef


define elab_coverage
#!/bin/bash

vsim $(VSIM_PARAMS) $(COV_VSIM_OPT) $(SIM_LIB_LIST) -sv_seed $(SIM_SEED) $(ELAB_OPTIONS) $(SIM_LIB_DIR)/$(SIEMENS_TOP).$(COV_COMP)

endef


# Convert the raw string above into `echo -e` friendly strings
sim_coverage_str = $(subst ",\", $(subst $(newline),\n,$(sim_coverage)))
batch_coverage_str = $(subst ",\", $(subst $(newline),\n,$(batch_coverage)))
elab_coverage_str = $(subst ",\", $(subst $(newline),\n,$(elab_coverage)))
