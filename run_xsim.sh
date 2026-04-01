#!/bin/bash
set -e

# Directories
UVM_DIR="uvm"
MEM_SRC_DIR="mem/src"

# Clean up
rm -rf xsim.dir *.log *.jou *.pb

# Compile C++ DPI code
xsc ${UVM_DIR}/ref_model.cpp

# Compile RTL
xvlog -sv -L uvm \
    ${MEM_SRC_DIR}/cache.sv \
    ${MEM_SRC_DIR}/load_store_unit.sv \
    ${MEM_SRC_DIR}/l1_data_cache.sv

# Compile UVM package and top
xvlog -sv -L uvm \
    -i ${UVM_DIR} \
    -i ${MEM_SRC_DIR} \
    ${UVM_DIR}/lsu_l1d_pkg.sv \
    ${UVM_DIR}/tb_top.sv

# Elaborate
xelab -L uvm -sv_lib xsim.dir/work/xsc/dpi tb_top -s top_sim -timescale 1ns/1ps

# Run
xsim top_sim -R "$@"
