#!/usr/bin/env python3
import argparse
from build_dependency_files import parse_subs_yaml


def main(args):
    subs_dict = parse_subs_yaml(args.subsfilelist, args.srcbase, verbose=False)
    for key, value in subs_dict.items():
        if args.verbose:
            print(f"{key}: {value}")
        else:
            print(f"{key}", end=" ")


if __name__ == '__main__':
    argp = argparse.ArgumentParser(
        description='Resolve SUBSTITUTIONS list into a full list of substituted'
        ' modules')
    argp.add_argument('srcbase', help="path to source root")
    argp.add_argument('subsfilelist', help="location of yaml files that "
                      "describe module replacements. Should be space-"
                      "separated list of files.")
    argp.add_argument('-v', '--verbose', action='store_true', help='include path')
    args = argp.parse_args()
    main(args)
