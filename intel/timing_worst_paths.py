#!/usr/bin/env python3
import sys
import os
import re
from collections import Counter

report_size = 20

with os.popen('find . -name "*TQ*_200paths_setup.txt"') as setup_reports:
    setup_files = setup_reports.read().splitlines()

# remove builds that met timing
setup_files = [ii for ii in setup_files if "0.000" not in ii]
if not setup_files:
    print("Could not find any TimeQuest setup results under current directory")
    sys.exit(1)


SRC = 2
DST = 3
# Trim up the names so that buses and memory locations are combined
re_debus = re.compile(r'\[[0-9]+\]')
re_deram = re.compile(r'ram_block.*?;')

report_lines = []
for ii in setup_files:
    # A good line is "; -0.943 ; name ; name ; clk ; clk ; rel ; skew ; delay;"
    # Split(";")Index: 0   1      2      3      4     5     6     7       8
    lines = open(ii.strip(), 'r').read().splitlines()
    # Filter for good lines, and remove extra spaces in the line
    good_lines = [ll.replace(" ", "") for ll in lines if ll.startswith("; -")]
    # Clean up all the lines
    good_lines = [re.sub(re_debus, '', ll) for ll in good_lines]
    good_lines = [re.sub(re_deram, 'ram_block;', ll) for ll in good_lines]
    good_lines = [ll.replace("~DUPLICATE", "") for ll in good_lines]
    # Remove duplicate lines (caused by a single bus reported for each bit)
    good_lines = set(good_lines)
    # Add these lines to the total report
    report_lines += [line.split(";") for line in good_lines]

# report_lines contains an array of values per line of all the reports
paths = [(ii[SRC], ii[DST]) for ii in report_lines]
sources = [ii[SRC] for ii in report_lines]
destinations = [ii[DST] for ii in report_lines]

result = Counter(paths)
for (path, num) in result.most_common(report_size):
    print("From: %s" % path[0])
    print("To  : %s" % path[1])
    print("Cnt : %d" % num)
    print()
