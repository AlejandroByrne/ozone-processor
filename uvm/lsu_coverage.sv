`timescale 1ns/1ps
class lsu_coverage extends uvm_subscriber #(lsu_seq_item);
  `uvm_component_utils(lsu_coverage)

  // ── State for cross-transaction tracking ──
  bit [63:0] prev_addr;
  bit        prev_is_write;
  bit        prev_valid = 0;

  typedef enum { HAZ_NONE, HAZ_RAW, HAZ_WAR, HAZ_WAW, HAZ_RAR } hazard_e;
  hazard_e   cur_hazard;

  // ── Covergroups ──

  covergroup op_cg with function sample(lsu_seq_item item);
    // Basic operation type
    cp_op_type: coverpoint item.is_write {
      bins load  = {0};
      bins store = {1};
    }

    // Address set index — L1D has 8 sets, index = addr[8:6]
    cp_cache_set: coverpoint item.addr[8:6] {
      bins sets[] = {[0:7]};
    }

    // Address block tag — upper bits after set index
    cp_cache_tag: coverpoint item.addr[21:9] {
      bins low    = {[0:3]};
      bins mid    = {[4:15]};
      bins high   = {[16:$]};
    }

    // Inter-phase delay
    cp_phase_delay: coverpoint item.inter_phase_delay {
      bins zero   = {0};
      bins short_ = {[1:2]};
      bins long_  = {[3:$]};
    }

    // Operation x cache set — exercises all op types across all sets
    cx_op_set: cross cp_op_type, cp_cache_set;

    // Phase delay x op type
    cx_delay_op: cross cp_phase_delay, cp_op_type;
  endgroup

  covergroup hazard_cg with function sample(hazard_e haz, bit [2:0] cache_set);
    cp_hazard: coverpoint haz {
      bins raw = {HAZ_RAW};
      bins war = {HAZ_WAR};
      bins waw = {HAZ_WAW};
      bins rar = {HAZ_RAR};
      bins none = {HAZ_NONE};
    }
    cp_cache_set: coverpoint cache_set {
      bins sets[] = {[0:7]};
    }
    // Hazard type x cache set — ensures hazards are hit across all cache sets
    cx_haz_set: cross cp_hazard, cp_cache_set;
  endgroup

  covergroup addr_pattern_cg with function sample(lsu_seq_item item);
    // Same address as previous transaction
    cp_same_addr: coverpoint (prev_valid && item.addr == prev_addr) {
      bins yes = {1};
      bins no  = {0};
    }

    // Adjacent cacheline (spatial locality)
    cp_adjacent: coverpoint (prev_valid && (item.addr[21:6] == prev_addr[21:6] + 1 ||
                                            item.addr[21:6] == prev_addr[21:6] - 1)) {
      bins yes = {1};
      bins no  = {0};
    }

    // Same cache set, different tag (set conflict)
    cp_set_conflict: coverpoint (prev_valid &&
                                 item.addr[8:6] == prev_addr[8:6] &&
                                 item.addr[21:9] != prev_addr[21:9]) {
      bins yes = {1};
      bins no  = {0};
    }

    cp_op_type: coverpoint item.is_write {
      bins load  = {0};
      bins store = {1};
    }

    // Address patterns x operation type
    cx_same_addr_op: cross cp_same_addr, cp_op_type;
    cx_adjacent_op:  cross cp_adjacent,  cp_op_type;
    cx_set_conflict_op: cross cp_set_conflict, cp_op_type;
  endgroup


  function new(string name, uvm_component parent);
    super.new(name, parent);
    op_cg           = new();
    hazard_cg       = new();
    addr_pattern_cg = new();
  endfunction

  // ── Classify data hazard type between consecutive transactions ──
  function hazard_e classify_hazard(lsu_seq_item item);
    if (!prev_valid || item.addr != prev_addr) return HAZ_NONE;
    if (!prev_is_write && item.is_write)  return HAZ_WAR;   // load then store
    if (prev_is_write  && !item.is_write) return HAZ_RAW;   // store then load
    if (prev_is_write  && item.is_write)  return HAZ_WAW;   // store then store
    return HAZ_RAR;                                          // load then load
  endfunction

  // ── Called by analysis port on every request transaction ──
  function void write(lsu_seq_item t);
    op_cg.sample(t);
    addr_pattern_cg.sample(t);

    cur_hazard = classify_hazard(t);
    hazard_cg.sample(cur_hazard, t.addr[8:6]);

    // Update state for next comparison
    prev_addr     = t.addr;
    prev_is_write = t.is_write;
    prev_valid    = 1;
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("COV", $sformatf(
      "\n══════════════════════════════\n" +
      "  Coverage Summary\n" +
      "  op_cg:           %.1f%%\n" +
      "  hazard_cg:       %.1f%%\n" +
      "  addr_pattern_cg: %.1f%%\n" +
      "══════════════════════════════",
      op_cg.get_coverage(),
      hazard_cg.get_coverage(),
      addr_pattern_cg.get_coverage()), UVM_LOW)
  endfunction

endclass
