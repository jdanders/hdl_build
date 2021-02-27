#!/bin/bash
# This script is to help make determine if variables have changed since last
# time make was run. The parameters are the new string and a filename to store
# the last seen value.
variable=$(echo "${1}"|tr -d '\n')
filename=${2}
result="yes"

if [ $# -eq 2 ] && [ -f ${filename} ]; then
    old_variable=$(cat "${filename}" | tr -d '\n')
    if [ "${variable}" == "${old_variable}" ]; then
        result="no"
    fi
fi

echo -n ${result}
