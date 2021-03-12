# General Makefile tips

Incorrect sequencing of variables and variable assignments, including placement of Makefile `include` lines, cause many problems when using Makefiles. The use of non-deferred `:=` assignments improves performance, and is the normal assignment operator in the hdl_build makefiles. The following guidelines will help keep order correct:

* Variables to be used by the hdl_build makefiles need to be listed in the project makefile before including `build.mk`
* Hooks used in project makefiles should be added after including `build.mk`
* When using variables defined in the hdl_build Makefiles, it might make things simpler to use `=` assignments so that the order doesn't matter.

To debug unexpected Makefile behavior there are two vital tools provided by `make`.

* `make -p <target>` will dump the make data-base. This will help determine what targets actually look like by the time `make` is done with analysis. For example if a `$(presimlib_hook)` rule you've added is not working, add the `-p` parameter and search for the `bld/done/presimlib_hook.done` rule definition. If your extra rule is not listed as a dependency of that target, it won't work.
* `make -d <target>` will dump the exact sequence of steps taken by `make`. This will help determine why a target is being rerun when you don't expect it to, or what sequence of dependencies caused errors to happen. It is usually helpful to search for "newer" or "Must remake" strings in the output of `-d` to find where things actually happen, and then go back from there.

Both of the above parameters put out a huge amount of data, so it is best to pipe to `less` or redirect to a file.

# Detailed hdl_build steps

If the build is failing, it might be helpful to follow through these steps to identify where the failure might be.

* Makefile inclusion, round 1: all of the hdl_build makefiles are processed and included, variables are set, target recipes and dependencies are evaluated.

* Dependency analysis depends on including a top level `.d` file.
    * For example, in `questa.mk` there is a `ifneq (,$(SIM_DEPS))` statement that is looking to see if the requested target is in the list of targets that should result in dependency analysis. If so, `-include $(DEP_DIR)/$(TOP_TB).questa.d` is the line that forces `.d` Makefile generation, followed by round 2.
    * If the `make` target (in `$(MAKECMDGOALS)`) is not a build target (`clean` for example), then the requested target will run, no round 2 needed.

* Makefile generation: including a top level `.d` file hits the implicit rule for the `.d` generation. This step runs the `$(MAKEDEPEND_CMD)` for the top level, which generates all the `.d` files needed for the top `.d` file.
    * In `questa.mk`, the implicit `.d` target is `$(DEP_DIR)/%.questa.d`.
    * After running the build the first time, **all** of the `.d` files match the implicit rule, so `$(MAKEDEPEND_CMD)` will run for each dependency if one of the `.d` recipe dependencies gets updated.

* Makefile inclusion, round 2: Because the `.d` is included and was updated, that triggers `make` to start over on dependency analysis and run everything again.  On this second round, all of the `.d` files are included, so `make` has a full picture of the work that needs to be done.
    * All of the `.d` files add dependencies to the implicit `.o` recipe, which prompts the real compilation work to begin

* Project build starts due to dependency of the top level `.o` output file.
    * In `questa.mk` the `comp` rule depends on `$(DEP_DIR)/$(TOP_TB).questa.o`. The top level `.o` file is not done until all the sub `.o` files are done.
    * Once the top level `.o` files is done, all dependency work is complete.

* `.o` recipes:
    * The `questa.mk` `.o` recipe selects a command to run based on filetype and calls `run_questa.sh`. This script prepares parameters for `pretty_run.sh` and executes. The `questa.mk` `.o` files result in either `vlog` commands for modules or `includes` by the `.d` file into the final vsim command.
    * The `quartus.mk` `.o` recipe selects a command to run based on filetype and calls `run_quartus.sh`. This script prepares parameters for `pretty_run.sh` and executes. The `quartus.mk` `.o` files result in either individual tcl include files for modules, or the creation of `$(IP_MK)` makefiles for IP files.

* Once the `.o` recipe is done, tool specific rules start to execute. Rules that are not dependent on `.o` output start in parallel with the `.o` rules.
    * Because `quartus.mk` includes a new layer of make with `-include $(IP_MK)`, make reassesses rules a third time after the creation of the `$(IP_MK)` file.

# Logging

The `pretty_run.sh` script logs all steps to the `$(BLOG_DIR)` directory. The `pretty_run.sh` script enables detailed logging and concise output. If adding to the hdl_build system, using one of the existing `run_...` scripts will keep logging consistent and complete.

The `pretty_run.sh` logs the command followed by the output to the specified log file. It also logs the command it received to the logfile with a `.cmds` suffix. This is to aid in reproducing errors while trying to debug individual steps. The commands will work when run directly except for any environment variables that `make` has set.

# Specific tips

## Dependency missing from file

The dependency analysis step is logged in the `$(BLOG_DIR)/dependency_*.log` files. Running the command at the top of the log should get the same dependency results as the build system got.

All found dependencies are recorded as `.d` files in `$(DEP_DIR)`. If they aren't there after dependency analysis, there was a problem with the analysis.

If there is a missing dependency, the file in question might have exposed a weakness in the SV parser. To debug, add some `pdb` debug points to the dependency analysis scripts and identify how the dependency was missed. Contribute any improvements back to this project.

The `$(MAKEDEPEND_CMD)` script doesn't recreate existing dependency `.d` files, so delete `.d` files between test runs.

## Sim Library error

This is one of the trickier parts of the questa flow. In order to allow parallel compile of modules, each has to be in its own library. Because of how `vlib`, `vmap`, and `vlog` work, the libraries have to be created and mapped before any compilation actually begins.

The steps to make that happen are these:

* Create the `modelsim.ini` file. This is where mappings are ultimately stored
* Analyze the `$(SIM_LAST_DEPS)` variable to see if the dependencies of the top level module have changed.
* Create each library and record each module's presence with `<name>.seen` file and a map entry with `<name>.map` file in the $(SIM_LIB_DIR).
* Concatenate all the `.map` files and add the mappings to the `modelsim.ini` file.

The libraries are ready to start compiling after those steps are done.

If there are errors with missing libraries, or module compilation reports a missing dependency but the `.d` file exists for that dependency, there is likely a problem with the library creation dependencies.

Debug library issues by checking the appropriate library directories exist, `.seen` and `.map` files exist, and that the mappings were added to `$(MS_INI)` file.

## Unknown filetype in [questa/quartus]: bld/buildlogs

This error means that the `.o` command was run, but the `.d` file either doesn't exist or the `.d` file failed to add the file dependency to the `.o` rule. If the `.d` doesn't exist, see the "Dependency missing from file" section. If the `.d` file is missing the `.o` rule, there is a bug in `.d` files generation.

## No rule to make target 'bld/deps/<name>.quartus.o', needed by 'bld/tcl/include_files.tcl

This error means the the `.d` file is missing, which probably means the top level file has not been found.
