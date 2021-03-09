#!/bin/bash
# parameters: "ac output directory" "ac total"
ac_dir=${1}
ac_total=${2}

echo -----------------------------------------------------------------
grep "Found" ${ac_dir}'/autocheck_verify.rpt'
grep "AC Total" ${ac_dir}'/autocheck_verify.rpt'
echo -----------------------------------------------------------------
if [[ '0' == ${ac_total} ]]; then
  echo -e "${GREEN}Autocheck found no new issues${NC}"
  c=0;
else echo -e "${RED}Autocheck found ${ac_total} new issue(s)${NC}"
  c=1;
fi
echo -e "${O} Autocheck finished ${C} (see ${ac_dir}/autocheck_verify.rpt)"
echo -e "  ${LB}To view in GUI run:${NC} make ac"
echo -e "  ${LB}To run in console only:${NC} make ac_batch"
exit $c
