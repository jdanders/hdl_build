#!/bin/bash
# This script will only print errors on error, no output if successful
# parameters: "message to print" "command to run" "name of log"
msg=${1}
cmd=${2}
logfile=${3}

echo -n "$0 " > ${logfile}.cmds
printf "'%s' " "$@" >> ${logfile}.cmds
echo -e "\n" >> ${logfile}.cmds

truecmd=true
falsecmd="grep --color -iE \"Error[ :]|Fatal[ :]\" ${logfile}"

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
${SCRIPT_PATH}/pretty_run.sh "${1}" "${2}" "${3}" "${truecmd}" "${falsecmd}"
