#!/bin/bash
set -e

SIM_TOOL=questa make -e comp
SIM_TOOL=modelsim make -e comp
SYNTH_OVERRIDE=y make project
if [ ! $(ls -1 bld/deps | wc -l) -eq 36 ]; then
    echo "The number of deps don't match expected"
    exit 1
fi
if ! ls bld/deps/*questa* > /dev/null; then
    echo "No questa dependencies found"
fi
if ! ls bld/deps/*modelsim* > /dev/null; then
    echo "No modelsim dependencies found"
fi
if ! ls bld/deps/*quartus* > /dev/null; then
    echo "No quartus dependencies found"
fi
make cleanall
