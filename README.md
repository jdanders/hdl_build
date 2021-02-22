# Introduction

The build system is built on GNU Makefile with helper scripts that provide the following functionality:

* Perform dependency analysis that enables discovery and compilation of all dependent files from a top level file
* Generate simulation scripts, synthesis projects, and automatically generate QSYS systems and megafunction IP cores
* Execute simulation and synthesis target programs after completing all preparatory steps.

Run `make help` for a list of targets, and `make helpall` for descriptions.

To get started

* clone or copy the hdl_build directory into the root of your HDL git repository
* copy the `example.mk` file to your project build directory and rename it to `Makefile`
* edit `Makefile` to have the correct simulation top module name as `TOP_TB` and/or correct synthesis top module name as `TOP`
* run `make sim` or `make synth`
* you will probably need to tweak the `DEFAULT_SYNTH_TOOL` in `quartus.mk` to match your environment

See the full makefile examples for adding other features to your project Makefile.

To add new makefiles that are not upstreamed, create *_addon.mk or *_custom.mk makefiles in the `make` directory.

# Software Requirements

This build system depends on Intel Quartus and Mentor Questa for synthesis and simulation. Other tools could be added.

Mentor Questa needs to be in the path, and the default `modelsim.ini` file will be copied from the detected install path.

Quartus install path must have the string "pro" in it if using Quartus Pro, and must not have "pro" in it if using Quartus Standard. The default path name of `intelFPGA_pro` meets this requirement.

Python 3.6 or higher is required, with the PyYAML yaml package installed for substitution files. If Python 3.6 is not available, replace all the 'f' strings with .format strings.

The build system is designed to run within a git repository. To work outside of a repo see section "Outside of git".

# Coding Requirements

Module and include dependencies are automatically determined.

* Modules can only be implemented in files with any of the following extensions: `.v`, `.sv`, `.ip`, `.qsys`, `_qmw.v` (megawizard)
* The module name must be the same as the "base" of the filename. For example, module `bypass_fifo` could be implemented as `bypass_fifo.sv` or `bypass_fifo.qsys`.
    * Megafunction IP cores should be saved using the `_qmw.v` suffix. This is the only exception where the filename can be different than the module name. For example, a PLL called `clkgen` should be stored as `clkgen_qmw.v` from the megafunction wizard. The instance in the code should still be `clkgen` without the `_qmw` extension. The build system will automatically handle building the megafunction for synthesis.
* Only a single module definition is allowed per file.
* Header files included by preprocessor ``` `include``` must always have either a `.svh` or `.vh` extension.
* In cases where a module needs to be replaced with a sim-only or synth-only module, use `SIM_SUBSTITUTIONS` or `SYNTH_SUBSTITUTIONS`.

# Usage

## Including build system

The build system `hdl_build` directory should be placed at the top level of your HDL git repository. This could be as a git submodule, or just copied over.

The build system can be included in a local Makefile with the following include line in the makefile:

```make
include /path/to/hdl_build/make/build.mk
```

## Build structure

### build.mk

The **`build.mk`** file provides the entry point and the basic structure for the build system. Use `make help` for an up-to-date list of targets provided.

* Variables
    * **`SRC_BASE_DIR`** is available and holds the path of the directory that holds all source code.
    * **`BLD_DIR`** variable sets the name of the result directory of the build system.
    * **`EXTRA_DIRS`** variable: a list of space delineated directory names to add during dependency search. This is only useful for directories normally ignored by the build system or a directory outside the SRC_BASE_DIR directory.
    * **`IGNORE_DIRS`** variable: a list of space delineated directory names to ignore during dependency search.
    * Sets **`IGNORE_FILE`**`:= .ignore_build_system` which is a file you can add to directory to tell the build system to ignore that directory. Run `touch .ignore_build_system` in the desired directory to create the file.
    * **`SLOW`** variable: if you want it to run single-threaded instead of parallel try `SLOW=1 make target`
* Targets
    * **`clean`** and **`cleanall`** (aka **`nuke`**) clean up generated build files.
    * **`list_targets`** lists all known Makefile targets
    * **`print-%`** prints Makefile variables
        * `make print-BLD_DIR` for example
    * **`print-Makefiles`** lists all included makefiles
    * **`help`** and **`helpall`** provides brief and more verbose help
* Hooks
    * **`$(predependency_hook)`**: by adding a dependency the `$(predependency_hook)` target, calling Makefiles can insert recipes prior to dependency analysis

### questa.mk

The **`questa.mk`** file provides Questa simulator related targets and consumes the dependency analysis results of **`build.mk`**.

* Variables
    * **`TOP_TB`** is the top level module name
    * **`SIM_TOOL`** to set tool version, and uses **`DEFAULT_SIM_TOOL`** if not provided.
    * **`SIM_SUBSTITUTIONS`**: a space delineated list of either `module:filename` mappings, or a path to a yaml file defining mappings. If a mapping is blank, dependency matching for the module is blocked.
        * `SIM_SUBSTITUTIONS = $(shell git_root_path mocks/mock_all_ipcores.yml) eth_100g:$(shell git_root_path mocks/100g_sim_model.sv ignorememodule:`
    * Monitors variables prefixed with **`PARAM_`** and passes them to questa
        * `PARAM_NUM_PACKETS := 20` passes a parameter named NUM_PACKETS with value of 20 to vsim
    * **`VLOG_OPTIONS`** and will pass the provided options to each vlog command
    * **`VLOG_COVER_OPT`** and will pass the provided options to each vlog command
    * **`UVM_DPILIB_VLOG_OPT`** and will pass the provided options to each vlog command
    * **`VOPT_OPTIONS`** and will pass the provided options to the vopt command
    * **`VSIM_OPTIONS`** and will pass the provided options to the vsim command
    * **`VSIM_COVER_OPT`** and will pass the provided options to the vsim command
    * **`COV_COMMANDS`** and will pass the commands to the batch command
    * **`SIM_LIB_APPEND`** and will add the value to the end of the included libraries (like `-L mymodule`)
* Targets
    * **`deps`** create dependency files
    * **`comp`** compile source files
    * **`vopt`** optimize source files
    * **`sim`** run simulation GUI
    * **`elab_sim`** elaborate simulation files
    * **`batch`** run simulation script without GUI
    * **`filelist_sim`** list all files used in compilation
    * **`modules_sim`** list all modules detected in simulation
    * **`clean_questa`** recipe for target **`clean`**.
    * **`cleanall_questa`** recipe for target **`cleanall`**.
    * **`printquesta-%`** print variables that need questa-related processing to have meaning.
* Hooks
    * **`$(presimlib_hook)`**: hook for inserting recipes before generating simulation libraries
    * **`$(precomp_hook)`**: hook for inserting recipes before starting module compilation
    * **`$(presim_hook)`**: hook for inserting recipes before starting simulation

### quartus.mk

The **`quartus.mk`** file provides Quartus related targets and consumes the dependency analysis results of **`build.mk`**.

* Variables
    * **`TOP`** as the top level module name
    * **`SYNTH_TOOL`** to set a tool version, and uses **`DEFAULT_SYNTH_TOOL`** if not provided.
    * **`SYNTH_OVERRIDE`** to override tool checks. Tool checks ensure that the environment PATH matches version specified by **`SYNTH_TOOL`**.
    * **`SYNTH_SUBSTITUTIONS`**: a space delineated list of either `module:filename` mappings, or a path to a yaml file defining mappings. If a mapping is blank, dependency matching for the module is blocked.
        * `SYNTH_SUBSTITUTIONS = $(shell git_root_path mocks/s10_mocks.yml) eth_100g:$(shell git_root_path mocks/100g_core.ip simonly_check:`
    * **`DEVICE`** used as the FPGA part number when needed for IP gen (i.e. 10AS066N2F40I2SG).
    * **`FAMILY`** used as the FPGA part family when needed for IP gen (i.e. "Arria 10").
    * **`NUM_TIMING_TRIES`** to tell synth_timing number of tries before giving up on timing.
    * Monitors variables prefixed with **`PARAM__`** and passes them to quartus
        * `PARAM_NUM_PORTS := 1` passes a parameter named NUM_PORTS with value of 1 to quartus
    * **`QUARTUS_FILE`**: file path to a tcl file which should be included in the QSF file
    * **`XCVR_SETTINGS`**: file path to a transceiver settings tcl file which should be included in the QSF file (SHOULD DEPRECATE?)
    * Monitors variable **`SDC_FILE`**: file path to a SDC file which should be included in the QSF file
    * **`QSF_EXTRA`** contents are added into the QSF file
    * **`ARCHIVE_DIR`** for archive location, default is `$(BLD_DIR)/archive`
    * **`ARCHIVE_SUB_DIR`** for archive location, default is `build_YYYY_MM_DD-HH.MM-gitbranch`
    * **`ARCHIVE_FILE_PREFIX`** to prefix archive files, default is `archive_`
    * **`ARCHIVE_DEST`** which is the path archive files will be copied. Default is `$(ARCHIVE_DIR)/$(ARCHIVE_SUB_DIR)`
    * Detects whether Quartus Pro or Quartus Standard is being used and sets `VERILOG_MACRO STD_QUARTUS=1` if Standard is being used.
    * Sets `VERILOG_MACRO SYNTHESIS=1`
    * Adds `synth_global_settings.tcl` to QSF file
* Targets
    * **`project`** create target QSF file
    * **`quartus`** open Quartus GUI
    * **`git_info`** create git archive information file
    * **`ipgen`** generate all included IP files (IP, QSys, Megawizard)
    * **`elab_synth`** run synthesis through elaboration
    * **`map`** run synthesis through map
    * **`fit`** run synthesis through fit
    * **`asm`** run synthesis through assembler (no timing)
    * **`timing`** synthesis through timing analysis (no assembler)
    * **`run_timing_rpt`** generate timing report file
    * **`timing_rpt`** to print timing report
    * **`timing_check_all`** or **`timing_check_all_timing`** to test timing report for errors
    * **`synth`** to run all synthesis steps
    * **`fit_timing`**, **`asm_timing`**,  **`synth_timing`** targets to repeat above steps until either timing is met or **`NUM_TIMING_TRIES`** is met.
    * **`archive_synth_results`** copy synthesis results to archive directory **`ARCHIVE_DEST`**
    * **`synth_archive`** to run all synthesis steps and archive results
    * **`synth_archive_timing`** to run all synthesis steps until timing is met and archive results
    * **`filelist_synth`** list all files used in compilation
    * **`modules_synth`** list all modules detected in synthesis
    * **`clean_quartus`** recipe for target **`clean`**.
    * **`cleanall_quartus`** recipe for target **`cleanall`**.
    * **`printquartus-%`** print variables that need quartus-related processing to have meaning.
* Hooks
    * **`$(presynth_hook)`**: hook for inserting recipes before starting synthesis related work
    * **`$(post_qgen_ip_hook)`**: hook for inserting recipes after ip generation, before synthesis mapping

# Outside of git

If you want to use this outside of a git repository, you will need to override two paths in your Makefile, like this:

```make
override BUILD_PATH := /path/to/core/hdl_build
override SRC_BASE_DIR := /path/to/current/src_base_dir
TOP_TB = sandbox_module

include $(BUILD_PATH)/make/build.mk
```
