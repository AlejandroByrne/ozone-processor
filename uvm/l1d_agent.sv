`timescale 1ns/1ps

class l1d_agent extends uvm_agent;
  `uvm_component_utils(l1d_agent)

  l1d_driver    drv;
  l1d_monitor   mon;
  uvm_sequencer #(l1d_item) sqr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    drv = l1d_driver::type_id::create("drv", this);
    mon = l1d_monitor::type_id::create("mon", this);
    sqr = uvm_sequencer#(l1d_item)::type_id::create("sqr", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    drv.seq_item_port.connect(sqr.seq_item_export);
  endfunction
endclass
