#!/usr/bin/env python3
import os
import sys
import time
import re
import argparse
import random
import subprocess
from glob import glob

script_dir = os.path.dirname(os.path.realpath(__file__))
# Prepare slack history
slack_history = []

# Function to check timing report for a given target and return value or False
bad_timing_re = re.compile(r"Worst-case setup slack is -([0-9.]+)")

seed_str = "set_global_assignment -name SEED "

REAL_RUN = True


def get_args():
    parser = argparse.ArgumentParser(
        description=('Rerun Quartus fit until timing is met'))
    parser.add_argument('syndir', help="like bld/synth_top")
    parser.add_argument('project', help="like bld/synth_top/synth_top")
    parser.add_argument('mapdonefile', help="like bld/done/map.done")
    parser.add_argument('-n', '--num', default=10, type=int,
                        help="max number of fits to run, default 10")
    parser.add_argument('-d', '--debug', action='store_true',
                        help="Don't really run Quartus commands for debug")
    args = parser.parse_args()
    return args


def run(command):
    if REAL_RUN:
        result = subprocess.run(command, capture_output=True, shell=True)
        if result.returncode > 0:
            print(f"Failed: {command}")
            sys.exit(result.returncode)
        return result.stdout
    else:
        ''' This function can be used in place of run to test the flow '''
        if ("quartus" in command):
            path = command.split()[-1]
            print(f"Pretend {command} just ran...")
            if "sta" in command:
                if random.random() < 0.1:
                    time_str = "Worst-case setup slack is 0.00"
                elif random.random() < 0.3:
                    time_str = "Worst-case setup slack is -0.10"
                else:
                    time_str = f"Worst-case setup slack is -{random.random()*10}"
                open(path+".sta.rpt", 'w').write(time_str)
                open(path.rsplit('/', 1)[0]+"/TQ_fake", 'w').write("!")
            else:
                print("SEED: " + open(path + ".qsf").read())
        elif ("make" in command):
            print("Timing result here: All good!")
        else:
            print(f"Real fake run {command}")
            print(os.popen(command).read())




def check_map_present(syn_dir, project, map_dir, map_done):
    if os.path.exists(map_dir):
        run(f'rm -r {map_dir}')
    if os.path.exists(map_done):
        # Move this map result to a saved place to restore before each fit
        # TODO: is this step needed?
        os.rename(syn_dir, map_dir)
    else:
        print("Must synthesize project before calling this script")
        sys.exit(2)


def check_bad_timing(project):
    tname = f"{project}.sta.rpt"
    if os.path.exists(tname):
        timing = bad_timing_re.findall(open(tname, 'r').read())
        if timing:
            slack = max([float(ii) for ii in timing])
            return slack
        else:
            # No slack means good timing, return False
            return False
    else:
            # Hasn't been run yet, return True (no timing is bad timing)
        return True


def build_for_timing(syn_dir, project, map_dir, tmp_dir, num_runs):
    if os.path.exists(tmp_dir):
        run(f'rm -r {tmp_dir}')
    os.mkdir(tmp_dir)
    # Work through all valid seeds
    initial_seed = random.randint(1, 4096)  # is there a max number for SEED?
    for seed in range(initial_seed, initial_seed + num_runs):
        print("\n\nRunning through seed %d" % seed)
        print(time.ctime(), flush=True)

        # Copy mapped directory over, change the SEED, start fit
        if (os.path.exists(syn_dir)):
            os.system('rm -rf ' + syn_dir)
        run(f'cp -a {map_dir} {syn_dir}')
        # Tweak seed
        qsf = open(f'{project}.qsf', 'r').read()
        qsf = re.sub(rf"{seed_str}\d+", f"{seed_str}%d" % (seed), qsf)
        open(f'{project}.qsf', 'w').write(qsf)
        # Do build
        run(f"quartus_fit --read_settings_files=on --write_settings_files=off {project}")
        run(f"quartus_sta {project}")

        slack = check_bad_timing(project)

        if slack:
            if (type(slack) is float):
                pslack = f"{slack:0.3f}"
                print(f"Previous slack was -{pslack} ns")
                slack_history.append(str(slack))
                # Backup bad build
                new_dir = syn_dir + f"_{pslack}"
                # Don't overwrite existing result, make a unique name
                if (os.path.exists(new_dir)):
                    new_dir = f"{new_dir}_{time.time()}"
                    pslack = f"{pslack}_{time.time()}"
                os.rename(syn_dir, new_dir)
                # Save timing results to tmp_dir
                for fname in glob(f"{new_dir}/TQ*"):
                    new_fname = fname.replace(f'{new_dir}', f'{tmp_dir}')
                    new_fname = new_fname.replace('TQ', f'TQ_{pslack}')
                    os.rename(fname, new_fname)
            else:
                print(f"Some problem with slack detection? {slack}")


        # No timing slack, done
        else:
            print("Met timing")
            # Move timing results to final dir
            for fname in glob(f'{tmp_dir}/TQ*'):
                os.rename(fname, fname.replace(f'{tmp_dir}', f'{syn_dir}'))
            run(f'rm -rf {tmp_dir}')
            # Delete unneeded bad results
            for dname in glob(f'{syn_dir}_*'):
                run(f'rm -rf {dname}')
            run(f'rm -rf {map_dir}')
            return True
    return False


def main():
    args = get_args()
    if args.debug:
        open(args.project + ".qsf", 'w').write(f"{seed_str}1")
        global REAL_RUN
        REAL_RUN = False
    syn_dir = args.syndir
    map_dir = syn_dir + "_mapped"
    tmp_dir = syn_dir + "_results"
    check_map_present(syn_dir, args.project, map_dir, args.mapdonefile)
    timing_result = build_for_timing(syn_dir, args.project,
                                     map_dir, tmp_dir, args.num)
    # Clean up and report
    run('rm -rf bld/*_mapped')
    if slack_history:
        slack_history.sort()
        print("\n")
        print(f"Slack history of {args.project} is:\n-"
              + "\n-".join(slack_history))
    worst = run(script_dir + '/timing_worst_paths.py').decode(errors='ignore')
    print("\nMost frequent worst timing paths:")
    for ii in worst.splitlines()[:12]:
        print(ii)
    if timing_result:
        open(os.path.join(syn_dir, 'TQ_worst_paths.txt'), 'w').write(worst)
    else:
        print(f"Could not find timing solution after {args.num} tries")
        return 1


if __name__ == '__main__':
    sys.exit(main())
