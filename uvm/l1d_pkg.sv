`timescale 1ns/1ps
package l1d_pkg;

  // Global Parameters
  parameter int A = 3;
  parameter int B = 64;
  parameter int C = 1536;
  parameter int PADDR_BITS = 22;
  parameter int MSHR_COUNT = 2;
  parameter int TAG_BITS = 10;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // DPI-C: golden model
  import "DPI-C" function void l1d_model_reset();
  import "DPI-C" function int  l1d_model_request(int addr, longint data, int tag, int is_write);
  import "DPI-C" function int  l1d_model_fill(int block_addr,
      longint w0, longint w1, longint w2, longint w3,
      longint w4, longint w5, longint w6, longint w7);
  import "DPI-C" function int  l1d_model_pop_completion(output int tag, output longint data, output int is_write);
  import "DPI-C" function int  l1d_model_pending_count();

  // DPI-C: legacy flat-map (kept for reference)
  import "DPI-C" function void              mem_write(longint unsigned addr, longint unsigned data);
  import "DPI-C" function longint unsigned  mem_read(longint unsigned addr);
  import "DPI-C" function void              mem_reset();

  // Transaction
  `include "l1d_item.sv"

  // Agent components
  `include "l1d_driver.sv"
  `include "l1d_monitor.sv"
  `include "l1d_agent.sv"

  // Environment components
  `include "llc_responder.sv"
  `include "l1d_scoreboard.sv"
  `include "l1d_env.sv"

  // Sequences and tests
  `include "l1d_sequences.sv"
  `include "l1d_test.sv"

endpackage
