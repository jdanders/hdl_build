#!/bin/bash
# parameters: "dir to search" "output file"
dir=${1}
outfile=${2}

TIMING_SORT="xargs ls -1tr"

for rpt in $(find ${dir} -name "*.sta.rpt" | ${TIMING_SORT} | grep ".sta.rpt") ; do
  egrep -H "^;[^;]*; -[^;]*; [0-9]+.*" $rpt
  grep -Hn3 "Worst-case setup slack is -" $rpt || printf "\nNo timing errors in %s\n\n" $rpt
  egrep -Hn3 "Illegal .*[1-9].*" $rpt || printf "\nNo illegal assignments in %s\n\n" $rpt
  egrep -Hn3 "Unconstrained .*[1-9].*" $rpt || printf "\nNo unconstrained paths in %s\n\n" $rpt
  egrep -HA3 "Found combinational loop" $rpt || printf "\nNo combinational loops in %s\n\n" $rpt
  echo "========================================"
done > ${outfile}

find ${dir} -name "*.map.rpt" | xargs grep "Inferred latch" || printf "\nNo inferred latches\n\n" >> ${outfile}
