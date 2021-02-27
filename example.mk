#-*- makefile -*-
TOP = mod1
TOP_TB = mod1
QSF_EXTRA = set_instance_assignment -name VIRTUAL_PIN ON -to *

include /path/to/hdl_build/build.mk
