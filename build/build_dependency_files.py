#!/usr/bin/env python3
import os
import sys
import yaml
import argparse
from find_dependencies import find_deps

if (os.popen('git rev-parse --is-inside-work-tree 2> /dev/null').read()):
    filelist_cmd = (
        "git ls-files --cached --modified --others --full-name "
        "--exclude-standard {srcbase} | grep -i -e '.sv$' -e '.svh$' "
        "-e '.v$' -e '.vh$' -e {ignorefile}")
else:
    # Git ls-files is faster, but if not using git, this command works
    filelist_cmd = ("find {srcbase} | grep -i -e '.sv$' -e '.svh$' "
                    "-e '.v$' -e '.vh$' -e {ignorefile}")

svh_hdr = """ifeq (,$(findstring +{dirpath}",$(VLOG_INCLUDES)))
  VLOG_INCLUDES += "+incdir+{dirpath}"
endif
"""

o_string = "$(DEP_DIR)/{name}.{prefix}.o: {path}"
o_dep_string = "\\\n\t$(DEP_DIR)/{dep}.{prefix}.o"
d_string = "$(DEP_DIR)/{name}.{prefix}.d: {path}"
incl_string = """ifeq (,$(filter $(DEP_DIR)/{dep}.{prefix}.d,$(MAKEFILE_LIST)))
-include $(DEP_DIR)/{dep}.{prefix}.d
endif
"""
dep_set_string = "{name}_DEPS := $(call uniq,"
incl_set_string = "{name}_INCLUDE := $(call uniq,"

seen_deps = []


def add_subs_module(args, module, filepath, subs_dict):
    if filepath:
        fullpath = os.path.join(args.srcbase, filepath.strip())
        subs_dict[module.strip()] = fullpath
    else:
        # No path means remove module
        subs_dict[module.strip()] = None
    return subs_dict


def parse_yaml(args, path):
    subs_dict = {}
    subs = yaml.load(open(path, 'r'), Loader=yaml.Loader)
    for module, filepath in subs.items():
        # Reserved word 'include' is a list of other yaml files
        if module == 'include':
            for path in filepath:
                fullpath = os.path.join(args.srcbase, path)
                subs_dict.update(parse_yaml(args, fullpath))
        else:
            print(f"{path} subbed {module}: {filepath}")
            subs_dict = add_subs_module(args, module, filepath, subs_dict)
    return subs_dict


def parse_subs_yaml(args):
    subs_dict = {}
    subs = args.subsfilelist.replace('"','').replace("'",'')
    subs_files = [subs_map.strip() for subs_map in subs.split()]
    for subs_map in subs_files:
        if subs_map:
            if ':' in subs_map:
                # Single entries are 'module: filepath'
                module, filepath = subs_map.split(':')
                print(f"Direct subs {module}: {filepath}")
                subs_dict = add_subs_module(args, module, filepath, subs_dict)
            else:
                # Otherwise it is a yaml file of entries
                subs_dict.update(parse_yaml(args, subs_map))
    return subs_dict


def find_module(name, filelist, subs_dict):
    if name in subs_dict:
        return subs_dict[name]
    # Make module names unique file basenames, prefix path sep and add period
    fname = os.path.sep + name
    if "." not in name:
        fname = fname + "."
    matched_paths = [path for path in filelist if fname in path]
    if len(matched_paths) > 1:
        matches = " : ".join(matched_paths)
        print(f"Warning: found multiple file entries for {name}: {matches}")
        print()
    if len(matched_paths) == 0:
        # No match
        return None
    return matched_paths[0]


def write_depfile(name, filelist, subs_dict, args):
    global seen_deps
    print(name)
    path = find_module(name, filelist, subs_dict)
    if path is None:
        return
    text = open(path, 'r').read()
    prefixes = args.outprefixlist.split(',')
    ostrings = {}
    dstrings = {}
    istrings = {}

    for prefix in prefixes:
        ostrings[prefix] = o_string.format(**locals())
        dstrings[prefix] = d_string.format(**locals())
        istrings[prefix] = ""
    if (name.endswith('.svh') or name.endswith('.vh')):
        dirpath = os.path.dirname(path)
        for prefix in prefixes:
            ostrings[prefix] = svh_hdr.format(**locals()) + ostrings[prefix]
    incl_var_string = incl_set_string.format(**locals())
    dep_var_string = dep_set_string.format(**locals())
    if ".sv" not in path and ".v" not in path:
        deps = []
    else:
        deps = find_deps(path, name, text, args)
    print(f"Processing dependencies for {name}: {deps}")
    #print(deps, path, name, args)
    for dep in deps:
        # TODO: find better way to remove dependency loops
        if (name == "lib_pkt_if_macros.svh"):
            continue
        dep_path = find_module(dep, filelist, subs_dict)
        # Unknown module found
        if dep_path is None:
            continue
        for prefix in prefixes:
            ostrings[prefix] += o_dep_string.format(**locals())
            istrings[prefix] += incl_string.format(**locals())
        if (dep.endswith('.svh') or dep.endswith('.vh')):
            incl_var_string += f" $({dep}_INCLUDE) {dep}"
            dep_var_string += f" $({dep}_DEPS)"
        else:
            incl_var_string += f" $({dep}_INCLUDE)"
            dep_var_string += f" $({dep}_DEPS) {dep}"
        fname = os.path.join(args.outdir, f"{dep}.{prefix}.d")
        # Don't recurse if the work has already been done
        if (dep in seen_deps):
            print(f"End recursion for {dep}, already seen")
            continue
        if (os.path.exists(fname)):
            print(f"End recursion for {dep}, already exists")
            continue
        seen_deps.append(dep)
        # Recurse through deps
        write_depfile(dep, filelist, subs_dict, args)
    for prefix in prefixes:
        ostrings[prefix] += "\n"
        dstrings[prefix] += "\n"
    #svstring += "\n"
    for prefix in prefixes:
        fname = os.path.join(args.outdir, f"{name}.{prefix}.d")
        open(fname, 'w').write(ostrings[prefix] + "\n"
                               + dstrings[prefix] + "\n"
                               + istrings[prefix] + "\n"
                               + dep_var_string + ")\n"
                               + incl_var_string + ")\n")


def main(args):
    # Figure out path to prefix each repo-relative path with
    if not args.srcbase:
        sys.exit(1)

    # Filelist paths are stored as absolute paths
    fcmd = filelist_cmd.format(srcbase=args.srcbase,
                               ignorefile=args.ignorefile)
    filelist = [os.path.join(args.srcbase, ii.strip()) for ii in
                os.popen(fcmd).readlines()]
    # Git lists duplicates, so set filter it
    filelist = list(set(filelist))
    ignoredirs = [os.path.dirname(f) for f in filelist if args.ignorefile in f]
    if args.ignoredirs:
        ignoredirs += [d.strip() for d in args.ignoredirs.split()]
    for idir in ignoredirs:
        print(f"Pruning {idir} from file list")
        filelist = [d for d in filelist if idir not in d]

    # Add extra directories to filelist
    if args.extradirs:
        dirs = [d.strip() for d in args.extradirs.split()]
        for d in dirs:
            files = [os.path.join(d, f) for f in os.listdir(d)]
            filelist += files

    subs_dict = {}
    if args.subsfilelist:
        subs_dict = parse_subs_yaml(args)

    name = args.name

    write_depfile(name, filelist, subs_dict, args)
    print(f"Processed dependencies for {name}, wrote to {args.outdir}")


if __name__ == '__main__':
    argp = argparse.ArgumentParser(
        description='Create dependency makefiles for all dependencies of named'
        ' module, using files in current repo and extradirs parameter')
    argp.add_argument('srcbase', help="path to source root")
    argp.add_argument('outdir', help="directory for output .d files")
    argp.add_argument('outprefixlist', help="comma separated list of prefixes"
                      " for the .o files")
    argp.add_argument('name', help="name of module to analyze")
    argp.add_argument('--extradirs', help="space-separated list of extra "
                      "non-repo directories to search")
    argp.add_argument('--subsfilelist', help="location of yaml files that "
                        "describe module replacements. Should be space-"
                        "separated list of files.")
    argp.add_argument('--ignorefile', nargs='?', default='.ignore_build_system',
                      help="directories containing a file with this "
                      "name will be ignored (default:.ignore_build_system)")
    argp.add_argument('--ignoredirs', help="comma-separated list of "
                      "directories to be ignored")
    argp.add_argument('-d', '--debug', action='store_true', help='print debug')
    args = argp.parse_args()
    main(args)
