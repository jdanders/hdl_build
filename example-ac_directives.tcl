netlist clock i_clk -period 10
netlist reset rst -active_high -async

autocheck enable

autocheck report item -status waived -type INIT_X_UNRESOLVED  -module lfsr -name en_delayed3
autocheck report item -status waived -type INIT_X_UNRESOLVED  -module up_delay -name in_r
