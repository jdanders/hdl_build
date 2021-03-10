#!/bin/bash
# parameters: "message to print" "command to run" "name of log" "success_cmd" "fail_cmd"
msg=${1}
cmd=${2}
logfile=${3}
success_cmd=${4}
fail_cmd=${5}

echo -n "$0 " >> ${logfile}.cmds
printf "'%s' " "$@" >> ${logfile}.cmds
echo -e "\n" >> ${logfile}.cmds

if [ -z ${VERBOSE} ]; then
    echo -e "${msg}"; echo "${cmd}" > ${logfile}
    if (eval "${cmd}") >> ${logfile} 2>&1; then
        (eval "${success_cmd}")
    else
        c=$?
        echo
        echo -e "${RED}Bad result from previous command${NC}: (see ${logfile})"
        echo ----------------
        (eval "${fail_cmd}")
        exit $c
    fi
else
    eval "${cmd}" | tee ${logfile} 2>&1
fi
