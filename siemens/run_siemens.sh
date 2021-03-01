#!/bin/bash
# parameters: "module name" "module path" "path to log directory"
# like: run_questa.sh "mymodule" "/dir/mymodule.sv" "${BLOG_DIR}"
modname=${1}
modpath=${2}
logdir=${3}
msg="${CLEAR}Compiling ${modname}${UPDATE}"


# Handle the different file types. Each needs a different command to compile.
# This script will not run correctly without all of the needed make env vars

# Commands
svh_cmd="echo \"${msg}\""

#TODO: create run_qsys so this works? Unneeded if qsys support in sim unneeded
qsys_cmd="mkdir -p ${QSYS_DIR}/${modname} &&
          cp ${SRC_BASE_DIR}/${modpath} ${QSYS_DIR}/${modname}/ &&
          export IP_SEARCH_PATHS_LOCAL=${SRC_BASE_DIR}/ip_cores/i2c_opencores &&
          ${BUILD_PATH}/scripts/run_qsys.sh ${modname}
            \"runclean \"${QGEN} ${QSYS_DIR}/${modname}/${modname}.qsys  --synthesis=VERILOG --output-directory=${QSYS_DIR}/${modname} --part=${SIM_DEVICE} --search-path=${IP_SEARCH_PATHS_LOCAL}\"\" ${logdir}/qsys_build_${modname}.log"

vlog_cmd="vlog -sv -work ${SIM_LIB_DIR}/${modname} ${VLOG_PARAMS} ${DEFAULT_SIM_LIB} ${SIM_LIB_LIST} ${modpath}"


if  [[ ${modpath} == *.svh || ${modpath} == *.vh ]]; then
# SVH files don't get compiled, and their makefile already included the dir
    msg="${CLEAR}Including directory for ${modname}${UPDATE}"
    cmd=$svh_cmd
    logfile="${logdir}/svh_${modname}.log"

else if [[ ${modpath} == *.sv || ${modpath} == *.v ]]; then
# Normal vlog file
    cmd=$vlog_cmd
    logfile="${logdir}/vlog_${modname}.log"

else
    echo "Unknown filetype to run_questa: ${modpath}"
    echo -en "Bad command: ${RED}$0 "
    printf "'%s' " "$@"
    echo -e "${NC}\n"
    exit 1
fi;fi


# Report parsing is different for qsys
if [[ ${modname} == *.qsys ]]; then
    truecmd=$(cat <<EOF
      if GREP_COLOR="0;40;1;33" grep -E --color "Warning:" ${logfile}; then
        echo -e "$O No errors but please check warnings in ${logfile} $C"
        echo
      else
        true
      fi
EOF
)
    falsecmd=$(cat <<EOF
      grep -E --color "(^\*\* Fatal[ :]|^\*\* Error[ :]|^\*\* [^W])" ${logfile}
      GREP_COLOR="0;40;1;33" grep -E --color "(Warning:|Error)" ${logfile}
EOF
)
else
    truecmd=$(cat <<EOF
       if GREP_COLOR="0;40;1;33" grep -P --color \
             "(Warning[ :]|^\*\* (?!Note: \(vlog-2286\)))" ${logfile}; then
           echo -e "$O No errors but please check warnings in ${logfile} $C"
           echo
       else
           true
       fi
EOF
)
    falsecmd=$(cat <<EOF
       grep -E --color \
           "(^\*\* Fatal[ :]|^\*\* Error[ :]|^\*\* [^W]|UVM_FATAL[ :]@)" \
           ${logfile};
       GREP_COLOR="0;40;1;33" grep -E --color "(^\*\* Warning[ :]|^\*\* [^E])" \
           ${logfile}
EOF
)
fi

echo -n "$0 " > ${logfile}.cmds
printf "'%s' " "$@" >> ${logfile}.cmds
echo -e "\n" >> ${logfile}.cmds


# To preserve escaped quotation marks
esc_truecmd=$(printf "%q" "$truecmd")
esc_falsecmd=$(printf "%q" "$falsecmd")

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
${SCRIPT_PATH}/../build/pretty_run.sh "${msg}" "${cmd}" "${logfile}" "${truecmd}" "${falsecmd}"
