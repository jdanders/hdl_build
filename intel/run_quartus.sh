#!/bin/bash
# parameters: 'message' 'command' 'path to log file'
# like: run_quartus.sh 'Compiling' 'ip-gen /dir/mymodule.ip' '${BLOG_DIR}/log.log'
msg=${1}
# translate \n back to newline
cmd=$(echo -e "${2}")
logfile=${3}

# Report parsing is different for qsys and ip
if [[ ${modname} == *.qsys || ${modname} == *.ip ]]; then
    success_cmd=$(cat <<EOF
        GREP_COLOR="0;40;1;33" grep -E --color "Warning:" ${logfile}\
            &&(echo -e "$O No errors but check warnings in ${logfile} $C";\
               echo)\
            ||true
EOF
)
    fail_cmd=$(cat <<EOF
        grep -E --color "(^\*\* Fatal[ :]|^\*\* Error[ :]|^\*\* [^W])"\
              ${logfile};\
        GREP_COLOR="0;40;1;33" grep -E --color "(Warning:|Error)" \
              ${logfile}
EOF
)
else
    success_cmd=$(cat <<EOF
        GREP_COLOR="0;40;1;33" grep -P --color \
             "(Warning[ :]|^\*\* (?!Note: \(vlog-2286\)))" ${logfile}\
        && (echo -e "$O No errors but check warnings in ${logfile} $C";\
            echo)\
        ||true
EOF
)
    fail_cmd=$(cat <<EOF
        grep -E --color "(^\*\* Fatal[ :]|^\*\* Error[ :]|^\*\* [^W])"\
              ${logfile};\
        GREP_COLOR="0;40;1;33"\
              grep -E --color "(^\*\* Warning[ :]|^\*\* [^E])" \
              ${logfile}
EOF
)
fi

echo -n "$0 " > ${logfile}.cmds
printf "'%s' " "$@" >> ${logfile}.cmds
echo -e "\n" >> ${logfile}.cmds

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
${SCRIPT_PATH}/../build/pretty_run.sh "${msg}" "${cmd}" "${logfile}" "${success_cmd}" "${fail_cmd}"
