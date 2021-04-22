#!/bin/bash
set -e

SIM_TOOL=questa make -e comp
SIM_TOOL=modelsim make -e comp
SIM_TOOL=vivado make -e comp
SYNTH_OVERRIDE=y make project
if [ ! $(ls -1 bld/deps | wc -l) -eq 48 ]; then
    echo "The number of deps don't match expected $(ls -1 bld/deps | wc -l)!=48"
    exit 1
fi
if ! ls bld/deps/*questa* > /dev/null; then
    echo "No questa dependencies found"
fi
if ! ls bld/deps/*modelsim* > /dev/null; then
    echo "No modelsim dependencies found"
fi
if ! ls bld/deps/*xsim* > /dev/null; then
    echo "No xsim dependencies found"
fi
if ! ls bld/deps/*quartus* > /dev/null; then
    echo "No quartus dependencies found"
fi
make cleanall
SIM_TOOL=vivado make -e cleanall
