# This is needed for subst command below
define newline


endef


define sim_do
vsim -i $(VSIM_PARAMS) $(SIM_LIB_LIST) -sv_seed $(SIM_SEED) $(SIM_LIB_DIR)/$(SIEMENS_TOP).$(TOP_COMP)

endef


define reheader
#To use, optionally pass a command: do resim.do run 100 ns
#To add logging, "log" as first param: do resim.do log run 100 ns
#If crash, restore: do $(BLD_DIR)/autobackup_restart.do
if {[runStatus] == "running"} {
    stop -sync
}
onerror abort
write format restart $(BLD_DIR)/autobackup_restart.do
write format wave $(BLD_DIR)/autobackup_wave_maybe.do
if {[file size $(BLD_DIR)/autobackup_wave_maybe.do] > 700} {
    mv $(BLD_DIR)/autobackup_wave_maybe.do $(BLD_DIR)/autobackup_wave.do
} else {
    rm $(BLD_DIR)/autobackup_wave_maybe.do
}

onerror abort
catch "make $(PRESIM_GOAL)" makeresult

echo $$makeresult
endef


define sim_get_cmd_params
    set nbrArgs 0
    if {$$argc > 0} {
        if { [string match "log" $$1] } {
            echo Logging all signals and memories...
            log -r /*  -nofilter Memory
            shift
        }
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
      $$cmd $$params
    }
endef


define restart
$(reheader)
if { [string match "*Bad result*" $$makeresult] } {
    echo "Make failed"
} else {
    restart -f
$(sim_get_cmd_params)
}

endef

define resim
$(reheader)
if { [string match "*Bad result*" $$makeresult] } {
    echo "Make failed"
} else {
    quit -sim
    onerror resume
    transcript file ""
    catch "mv $(TRANSCRIPT) $(TRANSCRIPT).[date +%Y%m%dT%H%M%S]" mvresult
    do $(BLD_DIR)/autobackup_restart.do
    onfinish stop
    transcript file $(TRANSCRIPT)
$(sim_get_cmd_params)
}

endef


define batch
#!/bin/bash

vsim $(VSIM_PARAMS) $(SIM_LIB_LIST) -sv_seed $(SIM_SEED) $(BATCH_OPTIONS) $(SIM_LIB_DIR)/$(SIEMENS_TOP).$(TOP_COMP)

endef

define elab
#!/bin/bash

vsim $(VSIM_PARAMS) $(SIM_LIB_LIST) -sv_seed $(SIM_SEED) $(ELAB_OPTIONS) $(SIM_LIB_DIR)/$(SIEMENS_TOP).$(TOP_COMP)

endef

# For help run command: qverify -c -do "autocheck compile -help"
define autocheck
onerror {exit 1}
do $(AC_DIRECTIVES)
autocheck compile -d $(SIM_LIB_DIR)/$(SIEMENS_TOP).$(SIEMENS_TOP) $(SIM_LIB_LIST)
autocheck verify
endef

# Convert the raw string above into `echo -e` friendly strings
sim_do_str = $(subst ",\", $(subst $(newline),\n,$(sim_do)))
restart_str = $(subst ',\', $(subst $(newline),\n,$(restart)))
resim_str = $(subst ',\', $(subst $(newline),\n,$(resim)))
batch_str = $(subst ",\", $(subst $(newline),\n,$(batch)))
elab_str = $(subst ",\", $(subst $(newline),\n,$(elab)))
autocheck_str = $(subst ",\", $(subst $(newline),\n,$(autocheck)))
