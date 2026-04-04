`timescale 1ns/1ps

module tb_top_l1d;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import l1d_pkg::*;

  // Parameters from package
  localparam int A = l1d_pkg::A;
  localparam int B = l1d_pkg::B;
  localparam int C = l1d_pkg::C;
  localparam int PADDR_BITS = l1d_pkg::PADDR_BITS;
  localparam int MSHR_COUNT = l1d_pkg::MSHR_COUNT;
  localparam int TAG_BITS = l1d_pkg::TAG_BITS;

  // Clocks and resets
  logic clk;
  logic rst_n;

  // Interfaces
  l1d_lsu_if lsu_if(clk, rst_n);
  llc_if     lc_if(clk, rst_n); // Use the existing llc_if

  // DUT Instantiation
  l1_data_cache #(
    .A(A), .B(B), .C(C), .PADDR_BITS(PADDR_BITS), .MSHR_COUNT(MSHR_COUNT), .TAG_BITS(TAG_BITS)
  ) dut (
    .clk_in(clk),
    .rst_N_in(rst_n),
    .cs_N_in(1'b0),     // Active low
    .flush_in(1'b0),    // Not testing flush yet

    // LSU Interface
    .lsu_valid_in(lsu_if.lsu_valid_in),
    .lsu_ready_in(lsu_if.lsu_ready_in),
    .lsu_addr_in(lsu_if.lsu_addr_in),
    .lsu_value_in(lsu_if.lsu_value_in),
    .lsu_tag_in(lsu_if.lsu_tag_in),
    .lsu_we_in(lsu_if.lsu_we_in),
    
    .lsu_valid_out(lsu_if.lsu_valid_out),
    .lsu_ready_out(lsu_if.lsu_ready_out),
    .lsu_addr_out(lsu_if.lsu_addr_out),
    .lsu_value_out(lsu_if.lsu_value_out),
    .lsu_write_complete_out(lsu_if.lsu_write_complete_out),
    .lsu_tag_out(lsu_if.lsu_tag_out),

    // LLC Interface
    .lc_ready_in(lc_if.lc_ready_in),
    .lc_valid_in(lc_if.lc_valid_in),
    .lc_addr_in(lc_if.lc_addr_in),
    .lc_value_in(lc_if.lc_value_in),

    .lc_valid_out(lc_if.lc_valid_out),
    .lc_ready_out(lc_if.lc_ready_out),
    .lc_addr_out(lc_if.lc_addr_out),
    .lc_value_out(lc_if.lc_value_out),
    .lc_we_out(lc_if.lc_we_out)
  );

  // Clock generation
  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  // Reset generation
  initial begin
    rst_n = 0;
    #20 rst_n = 1;
  end

  // UVM Setup
  initial begin
    uvm_config_db#(virtual l1d_lsu_if)::set(null, "*", "l1d_lsu_vif", lsu_if);
    uvm_config_db#(virtual llc_if)::set(null, "*", "llc_vif", lc_if);
    run_test();
  end

  // Global timeout
  initial begin
    #1_000_000;
    `uvm_fatal("TIMEOUT", "Simulation exceeded 1ms - likely deadlock")
  end

endmodule
