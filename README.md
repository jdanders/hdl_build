[![Toolless Test](https://github.com/jdanders/hdl_build/actions/workflows/runtest.yml/badge.svg?branch=master)](https://github.com/jdanders/hdl_build/actions/workflows/runtest.yml)

# Introduction

The build system is built on GNU Makefile with helper scripts that provide the following functionality:

* Perform dependency analysis that enables discovery and compilation of dependent files from a top level file
* Generate simulation scripts, synthesis projects, as well as QSYS systems and megafunction IP cores
* Execute simulation and synthesis target programs after completing all preparatory steps.

Run `make help` for a list of targets, and `make helpall` for descriptions.

To get started

* clone or copy the hdl_build repository
* to choose global default tools, create `defaults.mk`, or locally set `SIM_TOOL` and/or `SYNTH_TOOL` in your makefile
    * `defaults.mk` is placed in the root of the hdl_build repo. See `examples/example-defaults.mk` for a template
* copy the `examples/example.mk` file to your project build directory and rename it to `Makefile`
    * `example.mk` has the minimum for both sim and synth targets, with a QSF_EXTRA setting that will allow synthesis without worrying about pin assignments.
    * See `examples/example-full-sim.mk` and `examples/example-full-synth.mk` for examples of more options
* edit `Makefile`
    * add the correct simulation top module name as `TOP_SIM` and/or correct synthesis top module name as `TOP_SYNTH`
    * set correct path to the hdl_build repository. For flexibility, the examples use an environment variable `$HDL_BUILD_PATH` to help committed build files work in multiple environments, but a fixed path would work too.
* run `make sim` or `make synth`
    * synthesis projects require setting `FAMILY` and `DEVICE`

See the full makefile examples for adding other features to your project Makefile.

# Software Requirements

This build system depends on Intel Quartus, Siemens Questa or Modelsim, and Vivado xsim for synthesis and simulation. Other tools could be added.

The tool commands (`vsim`, `quartus`, etc.) need to be in the path already.

Quartus synthesis requires two variables in the use Makefile to create a project:

* `FAMILY`, for example `FAMILY := "Arria 10"`
* `DEVICE`, for example `DEVICE := 10AS123N2F40I2SG`


Quartus install path must have the string "pro" in it if using Quartus Pro, and must not have "pro" in it if using Quartus Standard. The default path name of `intelFPGA_pro` meets this requirement.

Python 3.6 or higher is required, with the PyYAML yaml package installed for substitution files. If Python 3.6 is not available, replace all the 'f' strings with .format strings.

The build system is designed to run within a git repository. To work outside of a repo see section "Outside of git".

## Extending hdl_build

To add new makefiles that are not upstreamed, create `*_addon.mk` or `*_custom.mk` makefiles in the base directory. These files will be included by `build.mk`, but keeping them as separate files reduces merge/rebase conflicts. The `_custom.mk` suffix is ignored by git and is intended to be used for files you do not want committed at all.

# Verilog Coding Requirements and Naming Conventions

Module, package, and include dependencies are automatically determined for verilog sources.

* Modules can only be implemented in files with `.v` or `.sv` extensions. Non-HDL modules like vendor IP are not discovered automatically and must be specified as a `subtitution`.
* The module name must be the same as the "base" of the filename. For example, module `fifo` could be implemented as `fifo.sv`.
    * Megafunction IP cores should be saved using the `_qmw.v` suffix. This is the only exception where the filename can be different than the module name. For example, a PLL called `clkgen` should be stored as `clkgen_qmw.v` (this is the file that has the megawizard settings embedded as comments). The module name in the code should still be `clkgen` without the `_qmw` extension. The build system will automatically handle building the megafunction for synthesis.
* Only a single module definition is allowed per file.
* Header files included by preprocessor ``` `include``` must use `.svh` or `.vh` extension.
* In cases where a module needs to be replaced with a sim-only or synth-only module, use `SIM_SUBSTITUTIONS` or `SYNTH_SUBSTITUTIONS`. Modules used as substitutions do not need follow any naming conventions because they will be found by direct path rather than the built-in search capability, but the module name used in the substitution must match the module being substituted.

# Usage

## Including the build system

The build system can be included in a local Makefile with the following include line in the makefile:

```make
include $(HDL_BUILD_PATH)/build.mk
```

or

```make
include /path/to/hdl_build/build.mk
```

* As a general guide:
    * variables used under `build.mk` need to be set before the include.
    * hooks are rules defined under `build.mk` need to be tied into after the include.
* The tool chain needs an entry point defined, such as `TOP_SIM` for simulation and `TOP_SYNTH` for synthesis.

## Build parameters and targets

### build.mk

The **`build.mk`** file provides the entry point and the basic structure for the build system. Use `make help` for an up-to-date list of targets provided.

* **`VERBOSE`**: Set VERBOSE=1 for a call to make to run fully verbose commands
* **`NOUPDATE`**: Set NOUPDATE=1 for a call to make to print every line instead of updating
* **`SLOW`**: Set SLOW=1 for a call to make to disable parallel building
* **`GIT_REPO`**: this variable is only defined if the Makefile is in a git repository (test if git repo with make's `ifdef`)
* **`SRC_BASE_DIR`**: directory that holds all relevant source code. Will be determined automatically if in a git repository.
* **`IGNORE_FILE`**: `touch .ignore_build_system` in a directory that should be ignored by the build system
* **`BLD_DIR`**: directory where build results are stored
* **`$(predependency_hook)`**: target hook to run something before dependency analysis
* **`SIM_TOOL`**: select which simulation tool should be used: modelsim, questa or qverify, vivado
* **`SYNTH_TOOL`**: select which synthesis tool should be used: quartuspro, quartus or vivado
* **`IGNORE_DIRS`**: a list of space delineated directory names to ignore during dependency search
* **`EXTRA_DIRS`**: a list of space delineated directory names to add during dependency search. This is only useful for directories normally ignored by the build system or a directory outside the `SRC_BASE_DIR` directory.
* **`clean`**: target to force redo of build steps and remove previous logs
* **`cleanall`**: target to remove all build results
* **`nuke`**: target to alias for cleanall
* **`list_targets`**: target to list all available Makefile targets
* **`print-%`**: target to use `make print-VARIABLE_NAME` to examine `VARIABLE_NAME`'s value.
    * `make print-BLD_DIR`
* **`print-Makefiles`**: target to print a list of all included makefiles
* **`help`**: target to show brief help.
* **`helpall`**: target to show this help.


### modelsim.mk or questa.mk

The **`modelsim.mk`** or **`questa.mk`** file provides simulator related targets and consumes the dependency analysis results of **`build.mk`**.

* **`TOP_SIM`**: identify the top module to be simulated with `TOP_SIM`. If not set, `TOP` will be used.
* **`SIM_SUBSTITUTIONS`**: a space delineated list of either `module:filename` mappings, or paths to a yaml file defining mappings. If a mapping is blank, dependency matching for the module is blocked. See `examples/example-subs.yml`.
    * `SIM_SUBSTITUTIONS = $(shell git_root_path sim_models/sim_all_ipcores.yml) eth_1g:$(shell git_root_path sim_models/1g_sim_model.sv ignorememodule:`
* **`SIM_LIB_APPEND`**: library string to appned to the library list, like `-L $(SIM_LIB_DIR)/customlib`
* **`deps`**: target to figure out sim dependencies only
* **`comp`**: target to compile simulation files
* **`vopt`**: target to perform vopt after compile
* **`filelist_sim`**: target to print list of files used in sim
* **`modules_sim`**: target to print list of modules used in sim
* **`AC_DIRECTIVES`**: Autocheck directives filename, default is ac_directives.tcl
* **`printquesta-%`**: use `make printquesta-VAR_NAME` to print variable after questa processing
* **`$(presimlib_hook)`**: target hook to run before sim libraries
* **`$(precomp_hook)`**: target hook to run before compilation
* **`$(presim_hook)`**: target hook to run before starting sim
* **`RESTART_SCRIPT`**: `bld/restart.do` can be used in the simulator to recompile source and restart the simulation using `restart -f`. The current session and waveform is backed up first. The first optional parameter is `log` which will log all signals and memories after restart. Following parameters will be executed after restart.
    * `do bld/restart.do log run 100 ns` will log things and then run for 100 ns. It can be helpful to tie the command to a keyboard shortcut.
* **`RESIM_SCRIPT`**: `bld/resim.do` can be used in the simulator to recompile source and restart the simulation using `quit -sim`. The current session and waveform is backed up first and the transcript is archived and cleared. The first optional parameter is `log` which will log all signals and memories after restart. Following parameters will be executed after restart.
    * `do bld/resim.do log run 100 ns` will log things and then run for 100 ns. It can be helpful to tie the command to a keyboard shortcut.
* **`VLOG_OPTIONS`**: options for `vlog` command
* **`VLOG_COVER_OPT`**: options for `vlog` coverage
* **`VOPT_OPTIONS`**: options for `vopt` command
* **`VSIM_OPTIONS`**: options for `vsim` command
* **`VSIM_COVER_OPT`**: options for `vsim` coverage
* **`COV_COMMANDS`**: commands to add to batch for coverage
* **`PARAM_*`**: monitors variables prefixed with **`PARAM_`** and passes them to simulator. `PARAM_NUM_PACKETS := 20` passes a parameter named NUM_PACKETS with value of 20.
* **`sim`**: target to run simulation in GUI
* **`elab_sim`**: target to run elaboration batch
* **`batch`**: target to run simulation batch
* **`autocheck_batch`**: (or `ac_batch`) Run autocheck in console only
* **`autocheck`**: (or `ac`) Run autocheck GUI


### vivado xsim.mk

The **`xsim.mk`** file provides Vivado simulator targets and consumes the dependency analysis results of **`build.mk`**.

* **`TOP_SIM`**: identify the top module to be simulated with `TOP_TB`. If not set, `TOP` will be used.
* **`printxsim-%`**: use `make printxsim-VAR_NAME` to print variable after xsim processing
* **`$(prexsimlib_hook)`**: target hook to run before xsim libraries
* **`$(prexcomp_hook)`**: target hook to run before compilation
* **`$(prexsim_hook)`**: target hook to run before starting xsim
* **`XVLOG_OPTIONS`**: options for `xvlog` command
* **`XELAB_OPTIONS`**: options for the `xelab` command
* **`XSIM_OPTIONS`**: options for `xsim` command
* **`SIM_SUBSTITUTIONS`**: a space delineated list of either `module:filename` mappings, or paths to a yaml file defining mappings. If a mapping is blank, dependency matching for the module is blocked. See `example-subs.yml`
* **`XSIM_LIB_APPEND`**: library string to appned to the library list, like `-L $(XSIM_LIB_DIR)/customlib`
* **`deps`**: target to figure out xsim dependencies only
* **`comp`**: target to compile simulation files
* **`filelist_xsim`**: target to print list of files used in xsim
* **`modules_xsim`**: target to print list of modules used in xsim
* **`PARAM_*`**: monitors variables prefixed with **`PARAM_`** and passes them to xsimulator. `PARAM_NUM_PACKETS := 20` passes a parameter named NUM_PACKETS with value of 20.
* **`elab_sim`**: target to run elaboration batch
* **`sim`**: target to run simulation in GUI
* **`batch`**: target to run simulation batch


### quartus.mk

The **`quartus.mk`** file provides Quartus related targets and consumes the dependency analysis results of **`build.mk`**.

* **`TOP_SYNTH`**: identify the top module to be simulated with `TOP_SYNTH`. If not set, `TOP` will be used.
* **`FAMILY`**: identify the FPGA product family, like "Stratix 10" or "Agilex". Should match Quartus string in project settings
* **`DEVICE`**: identify the FPGA device part number, should match Quartus string in project settings
* **`NUM_TIMING_TRIES`**: tell synth_timing number of tries before giving up on timing
* **`$(presynth_hook)`**: target hook to run before any synth work
* **`$(post_qgen_ip_hook)`**: target hook to run after ip generaation is done, before mapping
* **`printquartus-%`**: use `make printquartus-VAR_NAME` to print variable after Quartus processing
* **`SYNTH_OVERRIDE`**: synthesis enforces `SYNTH_TOOL` version match against tool on `PATH`. Run make with `SYNTH_OVERRIDE=1` to ignore the check.
* **`SYNTH_SUBSTITUTIONS`**: a space delineated list of either `module:filename` mappings, or paths to a yaml file defining mappings. If a mapping is blank, dependency matching for the module is blocked. See `examples/example-subs.yml`.
    * `SYNTH_SUBSTITUTIONS = $(shell git_root_path mocks/s10_mocks.yml) eth_100g:$(shell git_root_path mocks/100g_core.ip simonly_check:`
* **`QUARTUS_FILE`**: file path to a tcl file for Quartus settings that will be included in the QSF
* **`XCVR_SETTINGS`**: file path to a tcl file for transciever settings that will be included in the QSF
* **`SDC_FILE`**: file path to an SDC timing constraints file that will be used in the QSF
* **`QSF_EXTRA`**: a variable string that will be included directly in QSF
* **`filelist_synth`**: print list of files used in synth
* **`modules_synth`**: print list of modules used in synth
* **`PRO_RESULT`**: track whether Quartus Pro or Std is being used. If Std, sets `VERILOG_MACRO STD_QUARTUS=1`. Always sets `VERILOG_MACRO SYNTHESIS=1`
* **`PARAM_*`**: monitors variables prefixed with **`PARAM_`** and passes them to Quartus. `PARAM_NUM_PORTS := 2` passes a parameter named NUM_PORTS with value of 2.
* **`synth_tcl.mk`**: all QSF files get the values set in `synth_tcl.mk` global settings, including jtag.sdc
* **`project`**: target to create Quartus project
* **`quartus`**: target to open Quartus GUI
* **`quartus_fast`**: target to open Quartus GUI without waiting for ip generation
* **`git_info`**: target to archive git info in project directory
* **`ipgen`**: target to generate Quartus IP
* **`elab_synth`**: target to run through Quartus analysis and elaboration
* **`map`**: target to run through Quartus synthesis/mapping
* **`fit`**: target to run through Quartus fit
* **`asm`**: target to run through Quartus assembler (no timing)
* **`timing`**: target to run through Quartus timing (no assembler)
* **`run_timing_rpt`**: target to generate TQ_timing_report.txt
* **`fit_timing`**: target to run fit until timing is made
* **`asm_timing`**: target to Quartus assembler after running fit until timing is made
* **`synth`**: target to run full synthesis: map fit asm timing
* **`synth_timing`**: target to run full synthesis, running fit until timing is made
* **`ARCHIVE_DIR`**: archive base location, default is `$(BLD_DIR)/archive`
* **`ARCHIVE_SUB_DIR`**: archive subdirectory location, default is `build_YYYY_MM_DD-HH.MM-gitbranch`
* **`ARCHIVE_FILE_PREFIX`**: prefix archive files, default is `archive_`
* **`ARCHIVE_DEST`**: path archive files will be copied. Default is `$(ARCHIVE_DIR)/$(ARCHIVE_SUB_DIR)`
* **`archive_synth_results`**: target to archive synthesis results to `ARCHIVE_DEST`
* **`synth_archive`**: target to run full synthesis and archive when done
* **`synth_archive_timing`**: target to run full synthesis, running fit until timing is made, and archive when done
* **`timing_rpt`**: target to print timing report
* **`timing_rpt_timing`**: target to print timing report after repeating fit until timing is met
* **`timing_check_all`**: target to report timing problems
* **`timing_check_all_timing`**: target to report timing problems after repeating fit until timing is met


# Outside of git

If you want to use this outside of a git repository, you will need to set the source path in your Makefile like this:

```make
SRC_BASE_DIR := /path/to/current/src_base_dir
TOP_SIM = test_mod

include $(HDL_BUILD_PATH)/build.mk
```

If you are in a git repository, the `SRC_BASE_DIR` defaults to the root of the repository.
