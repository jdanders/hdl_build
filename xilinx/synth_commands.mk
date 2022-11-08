# This is needed for subst command below
define newline


endef

# The "$*" is replaced with the stem, which is the module name
# set $(fpath) to the filename
# set $(ftype) to "$(subst .,,$(suffix $(fpath)))" for filename suffix

# These define the commands to run for vivado .o files
define sv_cmd_raw
echo "read_verilog $(fpath)" > $(FILES_TCL).$*
endef


# Convert the raw string above into `echo -e` friendly strings
sv_cmd = $(subst ",", $(subst $(newline),\n,$(sv_cmd_raw)))
