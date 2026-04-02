`timescale 1ns/1ps

class l1d_item extends uvm_sequence_item;
  // Request fields
  rand bit          is_write;
  rand bit [9:0]    tag;
  rand bit [63:0]   addr;
  rand bit [63:0]   value;

  // Completion fields
  bit               completion_received;
  bit [63:0]        completion_value;

  // Addr must be 8-byte aligned
  constraint align_addr { addr[2:0] == 3'b000; }

  // More loads than stores typically
  constraint mix { is_write dist { 0 := 70, 1 := 30 }; }

  `uvm_object_utils_begin(l1d_item)
    `uvm_field_int(is_write, UVM_DEFAULT)
    `uvm_field_int(tag, UVM_DEFAULT)
    `uvm_field_int(addr, UVM_DEFAULT)
    `uvm_field_int(value, UVM_DEFAULT)
  `uvm_object_utils_end

  function new(string name = "l1d_item");
    super.new(name);
  endfunction

  function string convert2string();
    return $sformatf("%s tag=%0d addr=0x%0h val=0x%0h",
                     is_write ? "STORE" : "LOAD", tag, addr, value);
  endfunction
endclass
