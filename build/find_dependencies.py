#!/usr/bin/env python3
import os
import sys
import re
import argparse


# Package use pattern
package_use_re = re.compile('(\w+)::([\*\w]+)')

# Include use pattern
include_use_re = re.compile('`include\s+["<]([\w/\.\d]+)[">]')

# Module instance pattern, assuming parentheses contents removed
module_instance_re = re.compile(r'''
  (\w+)\s+          # module_identifier
  (?:\#\s*\(\)\s*)? # optional parameters
  (\w+)\s*          # instance name
  \(\)\s*           # port connections
  (?=;)             # statement end, don't consume
  ''', re.DOTALL | re.VERBOSE)

# These can fail with weird comments (like nested), but should be good enough
comment_line_re = re.compile(r'//.*')
comment_block_re = re.compile(r'/\*.*?\*/', re.DOTALL)
# Match literal quoted strings
quote_re = re.compile(r'".*?"')
# Enforce space before "#" in modules
add_space_re = re.compile(r'#\s*\(')

def de_parentheses(text):
    pstack = 0
    bstack = 0
    result = ""
    last_close = 0
    for i, c in enumerate(text):
        if c == '(':
            if not pstack and not bstack:
                result += text[last_close:i+1]
            pstack += 1
        elif c == '[':
            if not bstack and not pstack:
                result += text[last_close:i]
            bstack += 1
        elif c == ')' and pstack:
            last_close = i
            pstack -= 1
        elif c == ']' and bstack:
            last_close = i+1
            bstack -= 1
    result += text[last_close:]
    return result


keywords = [
    'accept_on', 'alias', 'always', 'always_comb',
    'always_ff', 'always_latch', 'and', 'assert', 'assign', 'assume',
    'automatic', 'before', 'begin', 'bind', 'bins', 'binsof', 'bit',
    'break', 'buf', 'bufif0', 'bufif1', 'byte', 'case', 'casex', 'casez',
    'cell', 'chandle', 'checker', 'class', 'clocking', 'cmos', 'config',
    'const', 'constraint', 'context', 'continue', 'cover', 'covergroup',
    'coverpoint', 'cross', 'deassign', 'default', 'defparam', 'design',
    'disable', 'dist', 'do', 'edge', 'else', 'end', 'endcase',
    'endchecker', 'endclass', 'endclocking', 'endconfig', 'endfunction',
    'endgenerate', 'endgroup', 'endinterface', 'endmodule', 'endpackage',
    'endprimitive', 'endprogram', 'endproperty', 'endspecify',
    'endsequence', 'endtable', 'endtask', 'enum', 'event', 'eventually',
    'expect', 'export', 'extends', 'extern', 'final', 'first_match',
    'for', 'force', 'foreach', 'forever', 'fork', 'forkjoin', 'function',
    'generate', 'genvar', 'global', 'highz0', 'highz1', 'if', 'iff',
    'ifnone', 'ignore_bins', 'illegal_bins', 'implements', 'implies',
    'import', 'incdir', 'include', 'initial', 'inout', 'input', 'inside',
    'instance', 'int', 'integer', 'interconnect', 'interface',
    'intersect', 'join', 'join_any', 'join_none', 'large', 'let',
    'liblist', 'library', 'local', 'localparam', 'logic', 'longint',
    'macromodule', 'matches', 'medium', 'modport', 'module', 'nand',
    'negedge', 'nettype', 'new', 'nexttime', 'nmos', 'nor',
    'noshowcancelled', 'not', 'notif0', 'notif1', 'null', 'or', 'output',
    'package', 'packed', 'parameter', 'pmos', 'posedge', 'primitive',
    'priority', 'program', 'property', 'protected', 'pull0', 'pull1',
    'pulldown', 'pullup', 'pulsestyle_ondetect', 'pulsestyle_onevent',
    'pure', 'rand', 'randc', 'randcase', 'randsequence', 'rcmos', 'real',
    'realtime', 'ref', 'reg', 'reject_on', 'release', 'repeat',
    'restrict', 'return', 'rnmos', 'rpmos', 'rtran', 'rtranif0',
    'rtranif1', 's_always', 's_eventually', 's_nexttime', 's_until',
    's_until_with', 'scalared', 'sequence', 'shortint', 'shortreal',
    'showcancelled', 'signed', 'small', 'soft', 'solve', 'specify',
    'specparam', 'static', 'string', 'strong', 'strong0', 'strong1',
    'struct', 'super', 'supply0', 'supply1', 'sync_accept_on',
    'sync_reject_on', 'table', 'tagged', 'task', 'this', 'throughout',
    'time', 'timeprecision', 'timeunit', 'tran', 'tranif0', 'tranif1',
    'tri', 'tri0', 'tri1', 'triand', 'trior', 'trireg', 'type', 'typedef',
    'union', 'unique', 'unique0', 'unsigned', 'until', 'until_with',
    'untyped', 'use', 'uwire', 'var', 'vectored', 'virtual', 'void',
    'wait', 'wait_order', 'wand', 'weak', 'weak0', 'weak1', 'while',
    'wildcard', 'wire', 'with', 'within', 'wor', 'xnor', 'xor'
]


def find_deps(path, name, text, args):
    ''' Process module contents to determine a list of dependencies
        path = repository relative path to file
        name = module name
        text = file contents
        args = arg parser object, looking for args.debug'''
    #print("Find deps args:", path, name, args)
    includes = []
    packages = []
    instances = []
    # Get includes
    include_search = include_use_re.findall(text)
    if include_search:
        for include_path in include_search:
            includes.append(os.path.basename(include_path))
    # Get packages
    package_search = package_use_re.findall(text)
    if package_search:
        for (pkg_name, fname) in package_search:
            packages.append(pkg_name)
    # Get instances -- clean up code for instance search first
    clean_text = quote_re.sub('', text)
    clean_text = comment_line_re.sub('', clean_text)
    clean_text = comment_block_re.sub('', clean_text)
    clean_text = add_space_re.sub(' #(', clean_text)
    clean_text = de_parentheses(clean_text)
    instance_search = module_instance_re.findall(clean_text)
    if instance_search:
        for (mod_name, inst_name) in instance_search:
            if mod_name not in keywords:
                instances.append(mod_name)
    dep_set = {obj for obj in includes + packages + instances if obj != name}
    return list(dep_set)


def main(args):
    name = args.name
    path = args.path
    text = open(path, 'r').read()
    deps = find_deps(path, name, text, args)
    print(f"{name} dependencies:")
    deps.sort()
    for mod in deps:
        print(f"\t{mod}")


if __name__ == '__main__':
    argp = argparse.ArgumentParser(
        description='Parse file and create list of dependencies')
    argp.add_argument('path', help="path of module to analyze")
    argp.add_argument('name', help="name of module to analyze")
    argp.add_argument('-d', '--debug', action='store_true', help='print debug')
    args = argp.parse_args()

    main(args)
