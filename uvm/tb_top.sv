// ═══════════════════════════════════════════════════════════════
//  Top-level UVM testbench for LSU + L1D integrated verification
//
//  DUT boundary:
//    ┌─────────────────────────────────────────────┐
//    │              DUT                            │
//    │  proc_if ──→ [ LSU ←──→ L1D ] ──→ llc_if   │
//    │                                             │
//    │  Driver                       LLC Responder │
//    │  Monitor ──→ Scoreboard + Coverage          │
//    └─────────────────────────────────────────────┘
//
// ═══════════════════════════════════════════════════════════════

`timescale 1ns/1ps

// RTL includes — adjust paths as needed for your simulator
`include "../mem/src/cache.sv"
`include "../mem/src/load_store_unit.sv"
`include "../mem/src/l1_data_cache.sv"
`include "../mem/src/mem_control/comb_util.sv"

// UVM interface definitions
`include "lsu_l1d_if.sv"

module tb_top;

  import uvm_pkg::*;
  import lsu_l1d_pkg::*;

  // ── Clock and reset ──
  logic clk;
  logic rst_n;

  initial begin
    clk = 0;
    forever #5 clk = ~clk;  // 100 MHz
  end

  initial begin
    rst_n = 0;
    #50;
    rst_n = 1;
  end

  // ── Interfaces ──
  lsu_proc_if  proc_if (.clk(clk), .rst_n(rst_n));
  llc_if       llc_vif (.clk(clk), .rst_n(rst_n));

  // ── Internal wires: LSU ↔ L1D ──
  logic         lsu_l1d_valid;
  logic         lsu_l1d_ready;
  logic [63:0]  lsu_l1d_addr;
  logic [63:0]  lsu_l1d_value;
  logic         lsu_l1d_we;
  logic [9:0]   lsu_l1d_tag;

  logic         l1d_lsu_valid;
  logic         l1d_lsu_ready;
  logic [63:0]  l1d_lsu_addr;
  logic [63:0]  l1d_lsu_value;
  logic         l1d_lsu_write_complete;
  logic [9:0]   l1d_lsu_tag;

  // ── DUT: Load-Store Unit ──
  load_store_unit #(
    .QUEUE_DEPTH (8),
    .TAG_WIDTH   (10)
  ) u_lsu (
    .clk_in               (clk),
    .rst_N_in             (rst_n),
    .cs_N_in              (1'b0),

    // Processor Instruction Interface (driven by UVM driver)
    .proc_instr_valid_in  (proc_if.proc_instr_valid),
    .proc_instr_tag_in    (proc_if.proc_instr_tag),
    .proc_instr_is_write_in(proc_if.proc_instr_is_write),

    // Processor Data Interface (driven by UVM driver)
    .proc_data_valid_in   (proc_if.proc_data_valid),
    .proc_data_tag_in     (proc_if.proc_data_tag),
    .proc_addr_in         (proc_if.proc_addr),
    .proc_value_in        (proc_if.proc_value),

    // L1D Interface (inputs from L1D)
    .l1d_valid_in         (l1d_lsu_valid),
    .l1d_ready_in         (l1d_lsu_ready),
    .l1d_addr_in          (l1d_lsu_addr),
    .l1d_value_in         (l1d_lsu_value),
    .l1d_tag_in           (l1d_lsu_tag),
    .l1d_write_complete_in(l1d_lsu_write_complete),

    // Processor Handshaking Outputs (monitored by UVM)
    .proc_instr_ready_out (proc_if.proc_instr_ready),
    .proc_data_ready_out  (proc_if.proc_data_ready),

    // L1D Interface (outputs to L1D)
    .l1d_valid_out        (lsu_l1d_valid),
    .l1d_ready_out        (lsu_l1d_ready),
    .l1d_addr_out         (lsu_l1d_addr),
    .l1d_value_out        (lsu_l1d_value),
    .l1d_we_out           (lsu_l1d_we),
    .l1d_tag_out          (lsu_l1d_tag),

    // Completion Interface (monitored by UVM)
    .completion_valid_out (proc_if.completion_valid),
    .completion_value_out (proc_if.completion_value),
    .completion_tag_out   (proc_if.completion_tag)
  );

  // ── DUT: L1 Data Cache ──
  l1_data_cache #(
    .A          (3),
    .B          (64),
    .C          (1536),
    .PADDR_BITS (22),
    .MSHR_COUNT (4),
    .TAG_BITS   (10)
  ) u_l1d (
    .clk_in     (clk),
    .rst_N_in   (rst_n),
    .cs_N_in    (1'b0),
    .flush_in   (1'b0),

    // LSU Interface (inputs from LSU)
    .lsu_valid_in (lsu_l1d_valid),
    .lsu_ready_in (lsu_l1d_ready),
    .lsu_addr_in  (lsu_l1d_addr),
    .lsu_value_in (lsu_l1d_value),
    .lsu_tag_in   (lsu_l1d_tag),
    .lsu_we_in    (lsu_l1d_we),

    // LSU Interface (outputs to LSU)
    .lsu_valid_out          (l1d_lsu_valid),
    .lsu_ready_out          (l1d_lsu_ready),
    .lsu_addr_out           (l1d_lsu_addr),
    .lsu_value_out          (l1d_lsu_value),
    .lsu_write_complete_out (l1d_lsu_write_complete),
    .lsu_tag_out            (l1d_lsu_tag),

    // Lower cache Interface (driven by LLC responder)
    .lc_ready_in  (llc_vif.lc_ready_in),
    .lc_valid_in  (llc_vif.lc_valid_in),
    .lc_addr_in   (llc_vif.lc_addr_in),
    .lc_value_in  (llc_vif.lc_value_in),

    // Lower cache Interface (monitored by LLC responder)
    .lc_valid_out (llc_vif.lc_valid_out),
    .lc_ready_out (llc_vif.lc_ready_out),
    .lc_addr_out  (llc_vif.lc_addr_out),
    .lc_value_out (llc_vif.lc_value_out),
    .lc_we_out    (llc_vif.lc_we_out)
  );

  // ── Register interfaces in config_db ──
  initial begin
    uvm_config_db#(virtual lsu_proc_if)::set(null, "*", "proc_vif", proc_if);
    uvm_config_db#(virtual llc_if)::set(null, "*", "llc_vif", llc_vif);
    run_test();
  end

  // ── Waveform dump (optional) ──
  initial begin
    if ($test$plusargs("WAVES")) begin
      $dumpfile("tb_top.vcd");
      $dumpvars(0, tb_top);
    end
  end

  // ── Global timeout ──
  initial begin
    #1_000_000;
    `uvm_fatal("TIMEOUT", "Simulation exceeded 1ms — likely deadlock")
  end

endmodule
