#!/bin/bash
# parameters: "message to print" "command to run" "name of log" "truecmd" "falsecmd"
msg=${1}
cmd=${2}
logfile=${3}
truecmd=${4}
falsecmd=${5}

echo -n "$0 " >> ${logfile}.cmds
printf "'%s' " "$@" >> ${logfile}.cmds
echo -e "\n" >> ${logfile}.cmds

if [ -z ${VERBOSE} ]; then
    echo -e "${msg}"; echo "${cmd}" > ${logfile}
    if (eval "${cmd}") >> ${logfile} 2>&1; then
        (eval "${truecmd}")
    else
        c=$?
        echo
        echo -e "Bad result from previous command: (see ${logfile})"
        echo ----------------
        (eval "${falsecmd}")
        exit $c
    fi
else
    eval "${cmd}" | tee ${logfile} 2>&1
fi
