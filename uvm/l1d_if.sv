`timescale 1ns/1ps

// Interface for the LSU facing side of L1D
interface l1d_lsu_if (input logic clk, input logic rst_n);
  // Inputs to L1D
  logic lsu_valid_in;
  logic lsu_ready_in;
  logic [63:0] lsu_addr_in;
  logic [63:0] lsu_value_in;
  logic [9:0] lsu_tag_in;
  logic lsu_we_in;

  // Outputs from L1D
  logic lsu_valid_out;
  logic lsu_ready_out;
  logic [63:0] lsu_addr_out;
  logic [63:0] lsu_value_out;
  logic lsu_write_complete_out;
  logic [9:0] lsu_tag_out;
endinterface

// Interface for the LLC facing side of L1D
interface l1d_llc_if (input logic clk, input logic rst_n);
  // Inputs to L1D
  logic lc_ready_in;
  logic lc_valid_in;
  logic [21:0] lc_addr_in;
  logic [511:0] lc_value_in;

  // Outputs from L1D
  logic lc_valid_out;
  logic lc_ready_out;
  logic [21:0] lc_addr_out;
  logic [511:0] lc_value_out;
  logic lc_we_out;
endinterface
