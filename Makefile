#
# Verilog Workflow Makefile
#
# Author:  Greg M. Crist, Jr. (gmcrist@gmail.com)
#
# Description:
#   General Makefile to be used for compiling, running testbenches, and running
#   signal waveform tools.
#
#   Defaults to VCS tools; falls back to Icarus Verilog if VCS is not installed
#

TARGET := $(shell basename "$(CURDIR)")
TB      = $(TARGET)_tb.v

COMPILER = vcs
VIEWER	 = dve

VCS_OPTS      = -PP +lint=TFIPC-L +lint=PCWM
IVERILOG_OPTS =

VCS := $(shell which vcs)

ifeq ($(VCS),)
COMPILER = iverilog
VIEWER   = gtkwave
endif


# Default target is to compile
all: $(TARGET)

# Compile the testbench using the specified tool
$(TARGET): $(COMPILER)

# Run the testbench
run: $(TARGET)
	@ ./$(TARGET)

# View the signal waveforms
view: $(VIEWER)


# Clean up local, temporary, and runtime files
clean:
	$(RM) $(TARGET)

	$(RM) -r $(TARGET).daidir
	$(RM) -r csrc
	$(RM) -r DVEfiles
	$(RM) ucli.key
	$(RM) vcdplus.vpd
	$(RM) vcdbasic.vcd
	$(RM) *~

# Compile using VCS
vcs:
	@ vcs $(VCS_OPTS) -o $(TARGET) $(TB)

# Use VCS DVE to view the signals
dve: run
	@ dve -vpd vcdplus.vpd &


# Compile using Icarus Verilog
iverilog:
	@ iverilog $(IVERILOG_OPTS) -o $(TARGET) -DIVERILOG *.v

# Use GTKWave to view the signals
gtkwave: run
	@ gtkwave vcdbasic.vcd &
