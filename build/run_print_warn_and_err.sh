#!/bin/bash
# This script will print warnings if present but successful, errors if not
# parameters: "message to print" "command to run" "name of log"
msg=${1}
cmd=${2}
logfile=${3}

echo -n "$0 " > ${logfile}.cmds
printf "'%s' " "$@" >> ${logfile}.cmds
echo -e "\n" >> ${logfile}.cmds

truecmd=$(cat <<EOF
  if GREP_COLOR="0;40;1;33" grep -E --color "Warning[ :]" ${logfile}; then
      echo -e "$O No errors but please check warnings in ${logfile} $C"
      echo
  else
    true
  fi
EOF
)
falsecmd="grep --color -iE \"Warning[ :]|Error[ :]|Fatal[ :]\" ${logfile}"

# To preserve escaped quotation marks
esc_truecmd=$(printf "%q" "$truecmd")

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
${SCRIPT_PATH}/pretty_run.sh "${1}" "${2}" "${3}" "${truecmd}" "${falsecmd}"
