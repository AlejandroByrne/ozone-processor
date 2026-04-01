`timescale 1ns/1ps
class lsu_seq_item extends uvm_sequence_item;

  // Stimulus fields
  rand bit          is_write;     // 1 = store, 0 = load
  rand bit [9:0]    tag;
  rand bit [63:0]   addr;
  rand bit [63:0]   value;        // store data (ignored for loads)
  rand int unsigned inter_phase_delay;  // cycles between instr and data phase

  // Response fields (filled by monitor on completion)
  bit [63:0]        completion_value;
  bit               completion_received;

  // ── Constraints ──

  // 8-byte aligned, fits in 22-bit physical address space
  constraint addr_aligned_c { addr[2:0] == 3'b0; }
  constraint addr_range_c   { addr < 64'h00400000; }

  // Keep inter-phase delay short (0 = same cycle as allowed by protocol)
  constraint delay_c { inter_phase_delay inside {[0:3]}; }

  // Bias toward smaller address space to force cache set conflicts
  // L1D has 8 sets, 64B blocks → set index = addr[8:6]
  constraint addr_set_bias_c {
    addr[21:9] dist { [0:3] := 70, [4:8191] := 30 };
  }

  `uvm_object_utils_begin(lsu_seq_item)
    `uvm_field_int(is_write,          UVM_ALL_ON)
    `uvm_field_int(tag,               UVM_ALL_ON)
    `uvm_field_int(addr,              UVM_ALL_ON)
    `uvm_field_int(value,             UVM_ALL_ON)
    `uvm_field_int(inter_phase_delay, UVM_ALL_ON)
  `uvm_object_utils_end

  function new(string name = "lsu_seq_item");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("%s tag=%0d addr=0x%0h val=0x%0h delay=%0d",
                     is_write ? "STORE" : "LOAD",
                     tag, addr, value, inter_phase_delay);
  endfunction

endclass
