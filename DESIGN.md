# General architecture

The hdl_build system core depends on `make` auto-dependency generation. The inspiration came from this document:

http://make.mad-scientist.net/papers/advanced-auto-dependency-generation/

The key principles to understand:

* when a Makefile includes another Makefile, that included Makefile becomes a dependency and can have a recipe that creates the included Makefile
* Makefile targets can have dependencies added at any point in the final Makefile database. Just state the `target: [dependency list]` without a recipe.

In order to adapt the structure to an HDL environment, several helper scripts are needed to get the `MAKEDEPEND` results described on that page. There are two scripts that accomplish that function:

* `find_dependencies.py`: given the text contents of a system verilog file, this script will return a list of dependency modules, packages, and included files.
* `build_dependency_files.py`: given a top level module name and source file base directory, this script creates the dependency makefiles (`.d` files) for each module, package, and included file that the top level depends on.
    * It also features substitution parameters, to force modules to be mapped to specific file. Because substitutions created different dependency trees, it is also important to name the dependency tree. This is done using the "outprefixlist" parameter.

Creating the .d files allows `make` to understand the dependencies of the project and efficiently build the system.

The basic structure of the auto-dependency generation is this:

```make
# How to create included .d makefiles
$(DEP_DIR)/%.d: | $(DEP_DIR) $(BLOG_DIR)
	@$(SCRIPTS)/run_full_log_on_err.sh  \
	 "Identifying dependencies for $*" \
	 "$(MAKEDEPEND_CMD) $(SUBS_QUESTA) $(MAKEDEP_TOOL_QUESTA) $*" \
	 $(BLOG_DIR)/dependency_$*.log

# How to process each project file
$(DEP_DIR)/%.o: | $(DEP_DIR) $(BLOG_DIR)
	@$(SCRIPTS)/run_tool.sh '$(VLOG_MSG)' '$(VLOG_CMD)' '$(BLOG_DIR)/vlog_$*.log'
	@touch $@

# Cause make to create the top level .d makefile
include $(DEP_DIR)/$(TOP).d
```

The `include` statement triggers the `.d` rule, which calls the `MAKEDEPEND_CMD` script, which creates the new `.d` files. After creating the `.d` file, `make` sees a dependency change (because `make` sees included Makefiles as dependencies) and evaluates the entire project again, including the new `.d` files this time.

The generated `.d` files have several responsibilities. Here is an example one:

```make
$(DEP_DIR)/mod1.o: /sd/hdl_build/test/mod1.sv\
	$(DEP_DIR)/pkg2.o\
	$(DEP_DIR)/submod2.o\
	$(DEP_DIR)/my_incl.svh.o\
	$(DEP_DIR)/pkg1.o\
	$(DEP_DIR)/submod1.o

$(DEP_DIR)/mod1.d: /sd/hdl_build/test/mod1.sv

ifeq (,$(filter $(DEP_DIR)/pkg2.d,$(MAKEFILE_LIST)))
-include $(DEP_DIR)/pkg2.d
endif
ifeq (,$(filter $(DEP_DIR)/submod2.d,$(MAKEFILE_LIST)))
-include $(DEP_DIR)/submod2.d
endif
ifeq (,$(filter $(DEP_DIR)/my_incl.svh.d,$(MAKEFILE_LIST)))
-include $(DEP_DIR)/my_incl.svh.d
endif
ifeq (,$(filter $(DEP_DIR)/pkg1.d,$(MAKEFILE_LIST)))
-include $(DEP_DIR)/pkg1.d
endif
ifeq (,$(filter $(DEP_DIR)/submod1.d,$(MAKEFILE_LIST)))
-include $(DEP_DIR)/submod1.d
endif

mod1_DEPS := $(call uniq, $(pkg2_DEPS) pkg2 $(submod2_DEPS) submod2 $(my_incl.svh_DEPS) $(pkg1_DEPS) pkg1 $(submod1_DEPS) submod1)
mod1_INCLUDE := $(call uniq, $(pkg2_INCLUDE) $(submod2_INCLUDE) $(my_incl.svh_INCLUDE) my_incl.svh $(pkg1_INCLUDE) $(submod1_INCLUDE))
```

Explanation of sections:

* add dependencies to the modules `.o` rule. This makes the result of this module dependent on the results of all the modules it depends on.
* make itself dependent on the source file. This causes the dependencies of the file to be recalculated if the file itself changes.
* include the `.d` files of the dependencies.
* maintain housekeeping variables `_DEPS` and `_INCLUDE`

The `.o` files are used to track when the processing completes for each design unit. In order to keep the Makefile as clean as possible, a `run_` script does the actual processing. The `run_` scripts get parameters indicating the module name and the path to the file the implements that module.

Each `.o` rule determines what it means to process each design unit. For simulation `questa.mk` runs `vlog` on design files. For synthesis `quartus.mk` adds design filenames to the project `tcl` file, and creates new Makefiles for IP generation of `qsys` files.

After the `run_` script completes, the `.o` file is `touch`ed so that `make` can track the completion.

## Only include `TOP.d` if needed

If the `TOP.d` file is always included, `make` can't do anything until that dependency analysis is done. This is not desirable when running help targets like `make clean`: you don't want to build up dependencies and then clean everything up.

To work around this, tool makefiles include an `if` statement to only include the `TOP.d` file if the `make` target is on a list of rules. To create that list, `make` calls the following `bash` magic.

```make
QUESTA_TARGETS := $(shell grep -oe "^[a-z].*:" $(BUILD_PATH)/siemens/questa.mk | grep -v clean | grep -v nuke | sed 's/:.*//')
```

That greps all the simple targets from `questa.mk`, removes `clean` and `nuke` targets, and then removes everything after `:` from the line. This results in a list of targets that **should** include the `TOP.d` file.

```make
SIM_DEPS := $(filter $(QUESTA_TARGETS),$(MAKECMDGOALS))
```

This looks at the list of targets given to `make` and filters for valid targets

```make
ifneq (,$(SIM_DEPS))
  -include $(DEP_DIR)/$(TOP_TB).questa.d
endif
```

If the result is not empty include the `TOP.d`

## Monitoring variables

There are several environmental variables the build system monitors for changes. Ideally these would be recorded in individual source files, but that was thought to reduce flexibility.

In order to compare variables between one build and another, a comparison is executed every time `make` runs, but it must result in a file update only if the comparison shows the value changed. The current scheme to do that looks like this for simulation parameters. The parameter being monitored is `$(SIM_PARAM)`.

```make
# Compare against old results, and force update if different
ifeq ($(shell $(SCRIPTS)/variable_change.sh "$(SIM_PARAM)" $(PARAMETER_DONE)),yes)
SIM_PARAM_DEP=$(PARAMETER_DONE).tmp
endif

# Update the parameters if any of the PARAM_ variable change
$(PARAMETER_DONE).tmp: | $(DONE_DIR)
	@echo "$(SIM_PARAM)" > $@
	@if [ ! -f $(PARAMETER_DONE) ]; then echo; echo "Recording PARAM_ parameters" && cp $@ $(PARAMETER_DONE); fi
$(PARAMETER_DONE): $(SIM_PARAM_DEP)
	@-diff $@.tmp $@ >/dev/null 2>&1 \
	    && rm $@.tmp \
	    || (echo "Updating PARAM_ parameters" && mv $@.tmp $@);
	@touch $@
```

The first statement compares the current variable value against the recorded file that stored the value seen last time you ran `make`.

* If the `variable_change.sh` script reports that it has changed, set sets a variable `SIM_PARAM_DEP`. This variable is a dependency on the recipe that will update the recorded value `$(PARAMETER_DONE)`.
    * If the variable is not set (values are equal) then the `$(PARAMETER_DONE)` recipe will not run.
        * The `$(PARAMETER_DONE)` remains untouched, so no new dependency work happens.
    * If the variable is set (value has been updated), the dependency `$(PARAMETER_DONE).tmp` will run and cause the `$(PARAMETER_DONE)` rule to run as a result.
        * The `$(PARAMETER_DONE)` file gets updated so all targets dependent on that file run again.

# Questa/Modelsim architecture

Simulation requires modules and packages compilation, headers file inclusion, and script generation to execute the simulator.

## Module and package compilation

The first step in questa prep is the creation of the libraries. In order to allow parallel compilation of modules, each needs its own library. Because of how `vlib`, `vmap`, and `vlog` work, the libraries have to be created and mapped before any compilation actually begins.

The steps to make libraries:

* Perform dependency analysis
* Create the `modelsim.ini` file. This is where mappings are ultimately stored
* Compare `$(SIM_TOP_DEPS)` to the `$(SIM_LAST_DEPS)` record to see if the dependencies of the top level module have changed
    * The dependency list comes from the `.d` file housekeeping described above).
* Create each library and record each module's presence with `<name>.seen` file and a map entry with `<name>.map` file in the `$(SIM_LIB_DIR)`.
    * A map entry is just: `submod1 = bld/simlib/submod1` for example
* Concatenate all the `.map` files and add the mappings to the `modelsim.ini` file.

The above steps must be complete before a `vlog` compilation is done.

## `.o` recipe and run_questa.sh

The `questa.mk` `.o` recipe supports `.svh/.vh` and `.sv/.v` files.

Module files run `vlog` according to the `vlog_cmd` variable in `questa.mk`

Header files have a special inclusion in their `.d` files.

```make
ifeq (,$(findstring +/path/hdl_build/test",$(VLOG_OPTIONS)))
  VLOG_OPTIONS += "+incdir+/sd/hdl_build/test"
endif
```

This adds includes the directory that holds the include file to the `VLOG_OPTIONS` `+incdir` parameter. Because of this inclusion, there really isn't any work for the `run_questa.sh` script to do, but it prints a message to acknowledge processing the file.

## Do files

The final step after compilation is to create `.do` files to run `vsim`. The templates are located in `do_files.mk` and are written to `.do` files in the `$(BLD_DIR)`.

# Quartus architecture

Synthesis requires building up the project file, generation of IP files, and execution of the quartus design flow.

Because Quartus Pro and Quartus Standard use different compilers, it can be necessary to know which tool is used. The quartus build defines a verilog macro that can be used in synthesizeable code `STD_QUARTUS`.

## Module and package inclusion

Each needed dependency is added to an independent `tcl` script file in the `$(TCL_DIR)`. After all the files are created they are concatenated into a `include_files.tcl` which contains all the needed source files. This file is combined with several other tcl files into the `project.tcl` file. The `project.tcl` file is fed into `quartus_sh` and creates the `.qsf` project file.

The other included project tcl files are:

* `$(GLOBAL_SYNTH_SETTINGS)` defines Quartus settings that are global for all builds
* `$(STD_V_PRO_MACRO_FILE)` defines the `STD_QUARTUS` macro
* `$(PARAMETER_TCL)` defines the parameters specified in the Makefile
* `$(SDC_SETTINGS)` defines the SDC timing parameters
* `$(QSF_EXTRA)` variable from the Makefile
* `$(IP_SEARCH_PATHS)` defined by include files

## '.o' recipe and run_quartus.sh

The `quartus.mk` `.o` recipe supports `.svh/.vh` and `.sv/.v` files, as well as Quartus `.ip`, `.qsys`, and megawizard verilog files ending in `_qmw.v`.

For verilog sources, appropriate lines are added to the project `tcl` files.

All IP Makefile templates and commands used for synthesis are stored in `synth_commands.mk`. The Makefiles create a `qip` target that runs a recipe to process the source IP file into a `.qip` file. That `.qip` file is both included in the project `tcl` file and added to the `$(DONE_DIR)/qgen_ip.done` dependency list. The `$(DONE_DIR)/qgen_ip.done` target must be complete before mapping/synthesis begins.

## Quartus processing

After `project.tcl` is processed into the project `.qpf` and `.qsf` files, targets are defined for each stage of processing. There are two paths:

* Default path runs through fit once
* The `_timing` path runs fit up to `NUM_TIMING_TRIES` times to make timing.

Because these are different dependency paths, everything starting with fit stage needs to differentiate between default and `_timing` targets. So `synth` and `synth_timing` are the full `synth` goal, but `synth_timing` repeats to make timing.

# Adding new tools or features

Features that will be contributed back to the main hdl_build project can follow the pattern of `quartus.mk` and `questa.mk`. For local changes that will be used internally but not contributed back, add a suffix of `_addon.mk` to the new makefile. For changes that will exist only in a local repo and won't be checked in, add a suffix of `_custom.mk`.

The suffixes of `_addon.mk` and `_custom.mk` will allow easy rebasing/merging of changes from the main `hdl_build` project without needing to maintain changes in the `hdl_build` files.

New makefiles benefit from following the following conventions:

* Include `help` target comments, which are signaled by `##` above the target line.

```makefile
## this is a help comment
mytarget: dep1 dep2
```
* Also helpful are header comments:
```makefile
## ----------------- #
# Questa build rules #
```

* If files are created, store files under the `$(BLD_DIR)` and add cleaning dependencies to `clean`, `cleanall`, or both.
* If the process doesn't create an obvious output file, create and touch a file in the `$(DONE_DIR)`.
* Include directory dependencies as order-only prerequisites
    * `mytarget: dep1 | $(BLD_DIR)`
* Be careful to get all dependencies accounted for, otherwise parallel building will cause inconsistent errors.
* Use colorful text using the `color.mk` variables, and prefer running commands through one of the `run_...` scripts.
    * `@echo;echo -e "$O Removing all build related files $C";echo`

## Basic requirements for adding make features

A feature makefile only needs to hook into the build system at some point. For example, a feature that builds a set of source files before compiling would tie into the `$(predependency_hook)` of `build.mk`. You could create a file `hdl_build/build_source_addon.mk` with these contents:

```make
#-*- makefile -*-
## ------------------ #
# MyAddon build rules #

SRC_BLD_DIR := $(BLD_DIR)/src_bld
SRC_RESULT := $(SRC_BLD_DIR)/generated.sv

$(SRC_BLD_DIR): | $(BLD_DIR)
	@mkdir -p $@

$(SRC_RESULT): src1.sv src2.sv | $(SRC_BLD_DIR)
	@run_build.sh $(SRC_BLD_DIR)

$(predependency_hook): $(SRC_RESULT)
```

A full tool makefile needs to define its own dependency `.d` and output `.o` rules. Here is a bare template file `hdl_build/newtool_addon.mk`.


```make
#-*- makefile -*-
## ------------------ #
# NewTool build rules #

# Build dependencies for NEWTOOL_SUBSTITUTIONS variable
# Compare against old results, and force update if different
ifeq ($(shell $(SCRIPTS)/variable_change.sh "$(NEWTOOL_SUBSTITUTIONS)" $(NEWTOOL_SUB_DONE)),yes)
NEWTOOLSUB_DEP=$(NEWTOOL_SUB_DONE).tmp
endif

# Update the substitutions if the NEWTOOL_SUBSTITUTIONS variable changes
$(NEWTOOL_SUB_DONE).tmp: $(DONE_DIR)
	@echo "$(NEWTOOL_SUBSTITUTIONS)" > $@
	@if [ ! -f $(NEWTOOL_SUB_DONE) ]; then echo "Recording NEWTOOL_SUBSTITUTIONS" && cp $@ $(NEWTOOL_SUB_DONE); fi
$(NEWTOOL_SUB_DONE): $(NEWTOOLSUB_DEP)
	@-diff $@.tmp $@ >/dev/null 2>&1 \
	    && rm $@.tmp \
	    || (echo "Updating NEWTOOL_SUBSTITUTIONS" && mv $@.tmp $@);
	@touch $@

##################### Module dependency targets ##############################

MAKEDEP_TOOL_NEWTOOL := "newtool"
SUBS_NEWTOOL := --subsfilelist '$(NEWTOOL_SUBSTITUTIONS)'

# The .d (dependent) targets are to calculate the dependencies of a file
# The .d recipe is run whenever the sv file changes
# The sv dependency is added in the .d file itself
# The '%' becomes the module name
# The '$*' is replaced by that module name
$(DEP_DIR)/%.newtool.d: $(NEWTOOL_SUB_DONE) $(predependency_hook) | $(DEP_DIR) $(BLOG_DIR)
	@$(SCRIPTS)/run_full_log_on_err.sh  \
	 "Running NewTool for $*$(UPDATE)" \
	 "$(MAKEDEPEND_CMD) $(SUBS_NEWTOOL) $(MAKEDEP_TOOL_NEWTOOL) $*" \
	 $(BLOG_DIR)/dependency_$*_newtool.log


##################### Include top level ##############################

# targets: grep lines that have ':', remove cleans, sed drop last character
# Extract all targets for synthesis:
NEWTOOL_TARGETS := $(shell grep -oe "^[a-z].*:" $(BUILD_PATH)/newtool_addon.mk | grep -v clean | grep -v nuke | sed 's/.$$//')

# When the top .d file is included, make can't do anything until built.
# Make sure it's included only when needed to avoid doing extra work
NEWTOOL_DEPS := $(filter $(NEWTOOL_TARGETS),$(MAKECMDGOALS))
ifneq (,$(NEWTOOL_DEPS))
  # The top .d file must be called out specifically to get the ball rolling
  # Otherwise nothing happens because there are no matches to the wildcard rule
  ifndef TOP_NEWTOOL
    $(error No TOP_NEWTOOL module defined)
  endif
  ifdef	TOP_NEWTOOL
    -include $(DEP_DIR)/$(TOP_NEWTOOL).newtool.d
  endif
endif

##################### Dependency targets ##############################
# Create rules to determine dependencies and create compile recipes for .sv
# The .o (out) rules are to mark that the file has been compiled
# The .o recipe is used to compile all files
# The source file dependency is added in the .d file
# The "$*" is replaced with the stem, which is the module name
# The "$(word 1,$^)" is the second dependency, which will be the sv filename

$(DEP_DIR)/%.newtool.o:  | $(DEP_DIR) $(BLOG_DIR)
	@if [ ! -f $(DEP_DIR)/$*.newtool.d ]; then echo -e "$(RED)Dependency .d file missing for $*$(NC)"; exit 1; fi
	@$(SCRIPTS)/run_newtool.sh $* $(word 1,$^) $(BLOG_DIR)
	@touch $@

```
