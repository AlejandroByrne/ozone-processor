`timescale 1ns/1ps
package l1d_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // Transaction
  `include "l1d_item.sv"

  // Agent components
  `include "l1d_driver.sv"
  `include "l1d_monitor.sv"
  `include "l1d_agent.sv"

  // Environment components
  // Need to import DPI C functions before including scoreboard
  import "DPI-C" function void mem_write(longint unsigned addr, longint unsigned data);
  import "DPI-C" function longint unsigned mem_read(longint unsigned addr);
  import "DPI-C" function void mem_reset();

  `include "llc_responder.sv"
  `include "l1d_scoreboard.sv"
  `include "l1d_env.sv"

  // Sequences and tests
  `include "l1d_sequences.sv"
  `include "l1d_test.sv"

endpackage
