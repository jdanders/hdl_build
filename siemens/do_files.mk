# This is needed for subst command below
define newline


endef


define run
onerror {resume}
write format restart autobackup_run_backup.do
write format wave autobackup_run_wave_maybe.do
# Only clobber the wave backup if there's real data
if {[file size autobackup_run_wave_maybe.do] > 1500} {
    mv autobackup_run_wave_maybe.do autobackup_run_wave.do
} else {
    rm autobackup_run_wave_maybe.do
}

quit -sim
vsim -i $(VSIM_PARAMS) $(DEFAULT_SIM_LIB) $(SIM_LIB_LIST) -sv_seed $(SIM_SEED) $(SIM_LIB_DIR)/$(TOP_TB).$(TOP_COMP)

endef


define redo
#To use, optionally pass a command: do run.do run 100 ns
#If crash, restore: do autobackup_run_backup.do
onerror {abort}
write format restart autobackup_run_backup.do
write format wave autobackup_run_wave_maybe.do
if {[file size autobackup_run_wave_maybe.do] > 1500} {
    mv autobackup_run_wave_maybe.do autobackup_run_wave.do
} else {
    rm autobackup_run_wave_maybe.do
}

make comp; restart -f;

set nbrArgs 0
if {$$argc > 2} {
    variable params ""
    set cmd $$1
    shift
    set nbrArgs $$argc
    for {set x 1} {$$x <= $$nbrArgs} {incr x} {
        set params [concat $$params $$1]
        shift
    }
}

if {$$nbrArgs > 0} {
  echo "True"
  $$cmd $$params
}

endef


define batch
#!/bin/bash

vsim $(VSIM_PARAMS) $(DEFAULT_SIM_LIB) $(SIM_LIB_LIST) -sv_seed $(SIM_SEED) $(BATCH_OPTIONS) $(SIM_LIB_DIR)/$(TOP_TB).$(TOP_COMP)

endef

define elab
#!/bin/bash

vsim $(VSIM_PARAMS) $(DEFAULT_SIM_LIB) $(SIM_LIB_LIST) -sv_seed $(SIM_SEED) $(ELAB_OPTIONS) $(SIM_LIB_DIR)/$(TOP_TB).$(TOP_COMP)

endef

# Convert the raw string above into `echo -e` friendly strings
run_str = $(subst ",\", $(subst $(newline),\n,$(run)))
redo_str = $(subst ',\', $(subst $(newline),\n,$(redo)))
batch_str = $(subst ",\", $(subst $(newline),\n,$(batch)))
elab_str = $(subst ",\", $(subst $(newline),\n,$(elab)))
