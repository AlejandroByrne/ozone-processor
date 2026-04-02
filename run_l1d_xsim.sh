#!/bin/bash
set -e

# Configuration (Set a default test if none is provided)
TEST_NAME=${1:-l1d_raw_test}
UVM_DIR="uvm"
MEM_SRC_DIR="mem/src"

echo "--- Building Simulation for Test: $TEST_NAME ---"

# Clean up
rm -rf xsim.dir *.log *.jou *.pb

# Compile C++ DPI code
xsc ${UVM_DIR}/ref_model.cpp

# Compile RTL
xvlog -sv -L uvm \
    ${MEM_SRC_DIR}/cache.sv \
    ${MEM_SRC_DIR}/l1_data_cache.sv

# Compile UVM package and top-level testbench
xvlog -sv -L uvm \
    -i ${UVM_DIR} \
    -i ${MEM_SRC_DIR} \
    ${UVM_DIR}/l1d_if.sv \
    ${UVM_DIR}/lsu_l1d_if.sv \
    ${UVM_DIR}/l1d_pkg.sv \
    ${UVM_DIR}/tb_top_l1d.sv

# Elaborate
xelab -L uvm -sv_lib xsim.dir/work/xsc/dpi tb_top_l1d -s l1d_sim -timescale 1ns/1ps

# Run the simulation
xsim l1d_sim -R -testplusarg UVM_TESTNAME=$TEST_NAME -testplusarg UVM_VERBOSITY=UVM_HIGH
