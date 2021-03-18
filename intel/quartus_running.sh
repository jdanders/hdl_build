#!/bin/bash

tmpfile=$(mktemp /tmp/quartus-running.XXXXXX)

trap quit INT
function quit() {
    rm -f $tmpfile
    trap "" EXIT
    exit 1
}

trap leave EXIT
function leave() {
    rm -f $tmpfile
    exit 0
}

# Check for running quartus tools
for cmdname in quartus_sh quartus_ipgenerate qsys-generate quartus_map quartus_syn quartus_cdb quartus_fit quartus_asm quartus_sta; do
    if pgrep ${cmdname} > /dev/null; then
        for pid in $(pgrep ${cmdname}); do
            search_pid=${pid}
            # traverse the parentage of pid to find make call
            while ! [[ "${search_pid}" == "" || "${search_pid}" -lt 1 ]]; do
                if [[ "${search_pid}" == "$PPID" ]]; then
                    # Common ancestor, ignore
                    break
                else
                    if echo $(ps -fp ${search_pid} -o comm=) | grep -q make; then
                        # This is the make call, but not the $PPID, add to list
                        echo ${pid} >> $tmpfile
                        break
                    fi
                    search_pid=$(ps -fp ${search_pid} -o ppid=)
                fi
            done
        done
    fi
done

# If any of the above tests recorded a pid, print the warning
if [ -s $tmpfile ]; then
    echo
    echo  -e "\e[31;7;5;1mBuild underway already:\e[25;27m \n  It looks like someone is already running synthesis on this machine\e[0m"
    xargs -r ps -wwo lstart,user:12,pid,cmd < $tmpfile
    echo
    echo "Type CTRL+C to exit, or wait to proceed"
    sleep 1
    echo "Proceeding..."
fi
