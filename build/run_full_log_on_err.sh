#!/bin/bash
# This script will print warn/err/fatal on success, and whole log if error
# parameters: "message to print" "command to run" "name of log"
msg=${1}
cmd=${2}
logfile=${3}

echo -n "$0 " > ${logfile}.cmds
printf "'%s' " "$@" >> ${logfile}.cmds
echo -e "\n" >> ${logfile}.cmds

truecmd=$(cat <<EOF
  if grep -E --color "Error[ :]|Fatal[ :]|UVM_FATAL [@ ]" ${logfile} ; then
    echo -e "$O Errors found, see ${logfile} $C"
    false
  else
    if GREP_COLOR="0;40;1;33" grep -E --color\
        "Warning[ :]|Error[ :]|Fatal[ :]" ${logfile}; then
      echo -e "$O Success, but please check messages in ${logfile} $C"
      echo
    else
      true
    fi
  fi
EOF
)
falsecmd="cat ${logfile}"

# To preserve escaped quotation marks
esc_truecmd=$(printf "%q" "$truecmd")

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
${SCRIPT_PATH}/pretty_run.sh "${1}" "${2}" "${3}" "${truecmd}" "${falsecmd}"
