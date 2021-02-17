#-*- makefile -*-
TOP = mod1
TOP_TB = mod1
QSF_EXTRA = set_instance_assignment -name VIRTUAL_PIN ON -to *

include $(shell git_root_path hdl_build/make/build.mk)
