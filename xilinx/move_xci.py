import re
import sys

assert(len(sys.argv) == 4)
infile = sys.argv[1]
outfile = sys.argv[2]
ipgen_path = sys.argv[3]

pattern_in  = r'"RUNTIME_PARAM.OUTPUTDIR">[a-zA-Z0-9\./\-\w\\]*</spirit:configurableElementValue>'
pattern_out = r'"RUNTIME_PARAM.OUTPUTDIR">' + ipgen_path + r'</spirit:configurableElementValue>'

with open(infile, 'r') as f:
    xci = f.read()

xci_out = re.sub(pattern_in, pattern_out, xci)

with open(outfile, 'w') as f:
    f.write(xci_out)
