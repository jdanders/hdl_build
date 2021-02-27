#!/bin/bash
# parameters: "module name" "module path" "path to log directory" "tcl output"
# like: run_quartus.sh "mymodule" "/dir/mymodule.sv" "${BLOG_DIR}" "out.tcl"
modname=${1}
modpath=${2}
logdir=${3}
tclfile=${4}
msg="${CLEAR}Adding ${modname}${UPDATE}"

# Handle the different file types. Each needs a different command to compile.
# This script will not run correctly without all of the needed make env vars

# Commands
svh_cmd="echo \"set_global_assignment -name SEARCH_PATH $(dirname ${modpath})\" > ${tclfile}.${modname}"

SCRIPT_PATH=$(dirname "$(readlink -f "$0")")
# These templates have four replacements strings handled by `sed` below
#   ipsearch, modname, modpath, and ftype
GEN_IP_TEMPLATE=${SCRIPT_PATH}/../make/template_ip.mk
GEN_QMW_TEMPLATE=${SCRIPT_PATH}/../make/template_qmegawiz.mk


# Qsys files need to be copied, modified for Pro tool, added to IP_MK/QSF files
qsys_cmd=$(cat <<EOF
  cp ${modpath} ${IP_DIR}/${modname}.qsys &&
  if [[  "${PRO_VERSION}" == "pro" ]] &&
         ! grep -q \"tool=\"QsysPro\"\" ${IP_DIR}/${modname}.qsys; then
      perl -pi -e "s^\\<component\\n^\\<component\\n   tool=\"QsysPro\"\\n^igs" -0 ${IP_DIR}/${modname}.qsys
  fi
  cat ${GEN_IP_TEMPLATE} | sed "s|ipsearch|${QSYS_IP_SEARCH_PARAM}|g" | sed "s|modname|${modname}|g" | sed "s|modpath|${modpath}|" | sed "s|ftype|qsys|" > ${IP_MK}.${modname}

  echo "set_global_assignment -name QIP_FILE ${IP_DIR}/${modname}/${modname}.qip" > ${tclfile}.${modname}
  echo "set_global_assignment -name IP_SEARCH_PATHS $(dirname ${modpath})" >> ${tclfile}.${modname}
EOF
)

# IP files need to be copied and added to IP_MK and QSF file
ip_cmd=$(cat <<EOF
  cp ${modpath} ${IP_DIR}/${modname}.ip &&
  cat ${GEN_IP_TEMPLATE} | sed "s| ipsearch||g" | sed "s|modname|${modname}|g" | sed "s|modpath|${modpath}|" | sed "s|ftype|ip|" > ${IP_MK}.${modname}
  echo "set_global_assignment -name QIP_FILE ${IP_DIR}/${modname}/${modname}.qip" > ${tclfile}.${modname}
EOF
)

# Megawizard .v files need to be added to IP_MK and QSF file
qmegawiz_cmd=$(cat <<EOF
  cat ${GEN_QMW_TEMPLATE} | sed "s| ipsearch||g" | sed "s|modname|${modname}|g" | sed "s|modpath|${modpath}|" | sed "s|ftype|qmegawiz|" > ${IP_MK}.${modname}
  echo "set_global_assignment -name QIP_FILE ${IP_DIR}/${modname}/${modname}.qip" > ${tclfile}.${modname}
EOF
)

# Everything else only needs to be added to QSF file
default_cmd="echo \"set_global_assignment -name SOURCE_FILE ${modpath}\" > ${tclfile}.${modname}"


if  [[ ${modname} == *.svh || ${modname} == *.vh ]]; then
# SVH files don't get compiled, and their makefile already included the dir
    msg="Including directory for ${modname}${UPDATE}"
    cmd=$svh_cmd
    logfile="${logdir}/svh_${modname}.log"

else if [[ ${modpath} == *.qsys ]]; then
# QSYS files get copied and then compiled
    cmd=$qsys_cmd
    logfile="${logdir}/qsys_${modname}.log"

else if [[ ${modpath} == *.ip ]]; then
# IP files get copied and then compiled
    cmd=$ip_cmd
    logfile="${logdir}/ip_${modname}.log"

else if [[ ${modpath} == *_qmw.v ]]; then
# Special suffix for megawizard source .v files
    cmd=$qmegawiz_cmd
    logfile="${logdir}/qmegawiz_${modname}.log"

else if [[ ${modpath} == *.sv || ${modpath} == *.v ]]; then
# Normal source file
    cmd=$default_cmd
    logfile="${logdir}/vlog_${modname}.log"

else
    echo "Unknown filetype to run_quartus: ${modpath}"
    echo -en "Bad command: ${RED}$0 "
    printf "'%s' " "$@"
    echo -e "${NC}\n"
    exit 1
fi;fi;fi;fi;fi


# Report parsing is different for qsys
if [[ ${modname} == *.qsys || ${modname} == *.ip ]]; then
    truecmd="GREP_COLOR=\"0;40;1;33\" grep -E --color \
             \"Warning:\" ${logfile}\
             &&(echo -e \"$O No errors but please check warnings in ${logfile} $C\";echo)||true"
    falsecmd="grep -E --color \"(^\*\* Fatal[ :]|^\*\* Error[ :]|^\*\* [^W])\"\
              ${logfile};\
              GREP_COLOR=\"0;40;1;33\"\
              grep -E --color \"(Warning:|Error)\" \
              ${logfile}"
else
    truecmd="GREP_COLOR=\"0;40;1;33\" grep -P --color \
             \"(Warning[ :]|^\*\* (?!Note: \(vlog-2286\)))\" ${logfile}\
             &&(echo -e \"$O No errors but please check warnings in ${logfile} $C\";echo)||true"
    falsecmd="grep -E --color \"(^\*\* Fatal[ :]|^\*\* Error[ :]|^\*\* [^W])\"\
              ${logfile};\
              GREP_COLOR=\"0;40;1;33\"\
              grep -E --color \"(^\*\* Warning[ :]|^\*\* [^E])\" \
              ${logfile}"
fi

echo -n "$0 " > ${logfile}.cmds
printf "'%s' " "$@" >> ${logfile}.cmds
echo -e "\n" >> ${logfile}.cmds

${SCRIPT_PATH}/pretty_run.sh "${msg}" "${cmd}" "${logfile}" "${truecmd}" "${falsecmd}"
