#!/bin/bash
# parameters: "ac verify report"
ac_report=${1}
ac_total="$(grep "AC Total" ${ac_report} | tr -s ' ' | cut -d ' ' -f 4)"

echo -----------------------------------------------------------------
grep "Found" ${ac_report}
grep "AC Total" ${ac_report}
echo -----------------------------------------------------------------
if [[ '0' == ${ac_total} ]]; then
  echo -e "${GREEN}# Autocheck found no new issues${C}"
  c=0;
else echo -e "${RED}# Autocheck found ${ac_total} new issue(s)${C}"
  c=1;
fi
echo -e "${O} Autocheck finished ${C} (see ${ac_report})"
echo -e "  ${LB}To view in GUI run:${NC} make ac"
echo -e "  ${LB}To run in console only:${NC} make ac_batch"
exit $c
