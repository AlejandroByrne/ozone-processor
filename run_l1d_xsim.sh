#!/bin/bash
set -e

# Configuration (Set a default test if none is provided)
TEST_NAME=${1:-l1d_cold_load_test}
UVM_DIR="uvm"
MEM_SRC_DIR="mem/src"
VERBOSITY=${2:-UVM_HIGH}

echo "--- Building Simulation for Test: $TEST_NAME ---"

# Clean up
rm -rf xsim.dir *.log *.jou *.pb

# Compile C++ DPI code
xsc ${UVM_DIR}/ref_model.cpp --gcc_compile_options "-I${UVM_DIR}"

# Compile UVM package and top-level testbench
xvlog -sv -L uvm \
    -i ${UVM_DIR} \
    -i ${MEM_SRC_DIR} \
    ${UVM_DIR}/l1d_pkg.sv

# Compile RTL
xvlog -sv -L uvm \
    -i ${UVM_DIR} \
    -i ${MEM_SRC_DIR} \
    ${MEM_SRC_DIR}/cache.sv \
    ${MEM_SRC_DIR}/l1_data_cache.sv

# Compile interfaces and top
xvlog -sv -L uvm \
    -i ${UVM_DIR} \
    -i ${MEM_SRC_DIR} \
    ${UVM_DIR}/l1d_if.sv \
    ${UVM_DIR}/lsu_l1d_if.sv \
    ${UVM_DIR}/tb_top_l1d.sv

# Elaborate
xelab -L uvm -sv_lib xsim.dir/work/xsc/dpi tb_top_l1d -s l1d_sim -timescale 1ns/1ps

# Run the simulation
echo "--- Running Test: $TEST_NAME (verbosity: $VERBOSITY) ---"
xsim l1d_sim -R -testplusarg UVM_TESTNAME=$TEST_NAME -testplusarg UVM_VERBOSITY=$VERBOSITY
