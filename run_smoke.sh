#!/bin/bash
set -e

# Directories
UVM_DIR="uvm"
MEM_SRC_DIR="mem/src"

# Clean up
rm -rf xsim.dir *.log *.jou *.pb

# Compile RTL
xvlog -sv \
    ${MEM_SRC_DIR}/cache.sv \
    ${MEM_SRC_DIR}/l1_data_cache.sv \
    mem/tb/l1d_smoke_tb.sv

# Elaborate
xelab l1d_smoke_tb -s smoke_sim -timescale 1ns/1ps

# Run
xsim smoke_sim -R
