# ═══════════════════════════════════════════════════════════════
#  UVM Testbench Build — LSU + L1D Memory Subsystem
# ═══════════════════════════════════════════════════════════════

# ── Simulator selection (override with: make SIM=vcs) ──
SIM ?= questa

# ── UVM home (adjust for your installation) ──
UVM_HOME ?= $(QUESTA_HOME)/verilog_src/uvm-1.2

# ── Source files ──
RTL_SRCS = \
	../mem/src/cache.sv \
	../mem/src/load_store_unit.sv \
	../mem/src/l1_data_cache.sv

UVM_SRCS = \
	lsu_l1d_pkg.sv \
	tb_top.sv

# ── Test selection (override with: make TEST=lsu_raw_test) ──
TEST ?= lsu_base_test
SEED ?= random
VERBOSITY ?= UVM_MEDIUM

# ═══════════════════════════════════════════════════════════════
#  Questa / ModelSim
# ═══════════════════════════════════════════════════════════════
ifeq ($(SIM),questa)

VLOG = vlog
VSIM = vsim

VLOG_FLAGS = -sv +incdir+. +incdir+../mem/src \
             -suppress 2583 -suppress 13314

VSIM_FLAGS = -c -do "run -all; quit -f" \
             +UVM_TESTNAME=$(TEST) \
             +UVM_VERBOSITY=$(VERBOSITY) \
             -sv_seed $(SEED)

compile:
	$(VLOG) $(VLOG_FLAGS) $(RTL_SRCS) $(UVM_SRCS)

run: compile
	$(VSIM) $(VSIM_FLAGS) tb_top

# Run with waveform dump
run_waves: compile
	$(VSIM) $(VSIM_FLAGS) +WAVES tb_top

# Regression: run all test classes with random seeds
regress: compile
	@for test in lsu_base_test lsu_load_test lsu_store_test lsu_raw_test \
	             lsu_waw_test lsu_eviction_test lsu_stress_test lsu_random_test; do \
		echo "═══ Running $$test ═══"; \
		$(VSIM) $(VSIM_FLAGS) +UVM_TESTNAME=$$test tb_top || exit 1; \
	done
	@echo "═══ All tests passed ═══"

endif

# ═══════════════════════════════════════════════════════════════
#  VCS
# ═══════════════════════════════════════════════════════════════
ifeq ($(SIM),vcs)

VCS = vcs
VCS_FLAGS = -full64 -sverilog -ntb_opts uvm-1.2 -timescale=1ns/1ps \
            +incdir+. +incdir+../mem/src \
            -debug_access+all

compile:
	$(VCS) $(VCS_FLAGS) $(RTL_SRCS) $(UVM_SRCS) -o simv

run: compile
	./simv +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(VERBOSITY) +ntb_random_seed=$(SEED)

regress: compile
	@for test in lsu_base_test lsu_load_test lsu_store_test lsu_raw_test \
	             lsu_waw_test lsu_eviction_test lsu_stress_test lsu_random_test; do \
		echo "═══ Running $$test ═══"; \
		./simv +UVM_TESTNAME=$$test +UVM_VERBOSITY=$(VERBOSITY) || exit 1; \
	done
	@echo "═══ All tests passed ═══"

endif

# ═══════════════════════════════════════════════════════════════
#  Xcelium
# ═══════════════════════════════════════════════════════════════
ifeq ($(SIM),xcelium)

XRUN = xrun
XRUN_FLAGS = -uvm -sv -64bit -timescale 1ns/1ps \
             +incdir+. +incdir+../mem/src \
             -access +rwc

compile run:
	$(XRUN) $(XRUN_FLAGS) $(RTL_SRCS) $(UVM_SRCS) \
	        +UVM_TESTNAME=$(TEST) +UVM_VERBOSITY=$(VERBOSITY)

endif

# ═══════════════════════════════════════════════════════════════
#  Utilities
# ═══════════════════════════════════════════════════════════════
clean:
	rm -rf work transcript vsim.wlf simv simv.daidir csrc \
	       *.vcd *.log ucli.key xcelium.d INCA_libs

.PHONY: compile run run_waves regress clean
