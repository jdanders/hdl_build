#!/bin/bash

export PATH=${PATH}:fake_bin:fake_msim/bin
make comp
SYNTH_OVERRIDE=y make project
if [ ! $(ls -1 bld/deps | wc -l) -eq 24 ]; then
    echo "The number of deps don't match expected"
    exit 1
fi
make cleanall
