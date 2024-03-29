#!/bin/bash
# parameters: 'message' 'command' 'path to log file'
# like: run_questa.sh 'Compiling' 'vlog /dir/mymodule.sv' '${BLOG_DIR}/log.log'
msg=${1}
cmd=${2}
logfile=${3}


# ignore vlog-2286 implicit include for uvm headers
success_cmd=$(cat <<EOF
       if grep -E --color "(\*?[*#] Fatal[ :]|\*?[*#] Error[ :]|UVM_ERROR [^:]|UVM_FATAL [^:])" ${logfile}; then
           echo -e "${RED}# Error detected $C (see ${logfile})"
           false
       else if GREP_COLOR="0;40;1;33" grep -P --color \
             "(Warning[ :]|\*?[*#] (Note: \((?!vlog-2286\))|Warning: \())" ${logfile}; then
           echo -e "$O No errors but please check warnings in ${logfile} $C"
           echo
       else
           true
       fi; fi
EOF
)
# TODO: ignore vcover-17363 missing modules until module list improves
fail_cmd=$(cat <<EOF
       if grep -q vcover-17363 ${logfile}; then echo "Module doesn't exist"; exit 0; fi
       GREP_COLOR="0;40;1;33" grep --no-group-separator -A1 -E --color "\*?[*#] Warning[ :]" \
           ${logfile}
       grep --no-group-separator -A1 -E --color \
           "(\*?[*#] Fatal[ :]|\*?[*#] Error[ :]|UVM_ERROR[ :]|UVM_FATAL[ :])" \
           ${logfile}
EOF
)

echo -n "$0 " > ${logfile}.cmds
printf "'%s' " "$@" >> ${logfile}.cmds
echo -e "\n" >> ${logfile}.cmds


# To preserve escaped quotation marks
esc_success_cmd=$(printf "%q" "$success_cmd")
esc_fail_cmd=$(printf "%q" "$fail_cmd")

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
${SCRIPT_PATH}/../build/pretty_run.sh "${msg}" "${cmd}" "${logfile}" "${success_cmd}" "${fail_cmd}"
RESULT=$?

# siemens tools sometimes segfault, try again
if tail -n4 ${logfile} | grep  "Unexpected signal: 11"; then
    echo "Segmentation Fault, try again"
    ${SCRIPT_PATH}/../build/pretty_run.sh "${msg}" "${cmd}" "${logfile}" "${success_cmd}" "${fail_cmd}"
    RESULT=$?
    if [ ${RESULT} -eq 0 ]; then
        exit ${RESULT}
    fi
fi
exit ${RESULT}
