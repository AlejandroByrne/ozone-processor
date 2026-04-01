#!/bin/bash
set -e

# 1. Compile C++ into a Xilinx-specific object format
xsc uvm/ref_model.cpp

# 2. Compile the SystemVerilog probe
xvlog -sv uvm/test_dpi.sv

# 3. Elaborate and Link the C++ and SystemVerilog
xelab test_dpi -s dpi_sim -sv_lib xsim.dir/work/xsc/dpi -timescale 1ns/1ps

# 4. Run it
xsim dpi_sim -R
