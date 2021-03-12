#-*- makefile -*-
TOP_TB = mod1
TOP_SYNTH = mod1

FAMILY = "Stratix 10"
DEVICE = 1SX280LU2F50E2VGS2
QSF_EXTRA = set_instance_assignment -name VIRTUAL_PIN ON -to *

include /path/to/hdl_build/build.mk
