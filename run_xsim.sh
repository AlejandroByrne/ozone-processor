#!/bin/bash
set -e

# 1. Configuration (Set a default test if none is provided)
TEST_NAME=${1:-lsu_base_test}
UVM_DIR="uvm"
MEM_SRC_DIR="mem/src"

echo "--- Building Simulation for Test: $TEST_NAME ---"

# 2. Compile C++ DPI code
xsc ${UVM_DIR}/ref_model.cpp

# 3. Compile RTL (The Cache and LSU)
xvlog -sv -L uvm \
    ${MEM_SRC_DIR}/cache.sv \
    ${MEM_SRC_DIR}/load_store_unit.sv \
    ${MEM_SRC_DIR}/l1_data_cache.sv

# 4. Compile UVM package and top-level testbench
xvlog -sv -L uvm \
    -i ${UVM_DIR} \
    -i ${MEM_SRC_DIR} \
    ${UVM_DIR}/lsu_l1d_pkg.sv \
    ${UVM_DIR}/tb_top.sv

# 5. Elaborate (Link everything together)
xelab -L uvm -sv_lib xsim.dir/work/xsc/dpi tb_top -s top_sim -timescale 1ns/1ps

# 6. Run the simulation
# We use -testplusarg to tell UVM which test class to instantiate
xsim top_sim -R -testplusarg UVM_TESTNAME=$TEST_NAME
