`timescale 1ns/1ps

class l1d_env extends uvm_env;
  `uvm_component_utils(l1d_env)

  l1d_agent       agent;
  llc_responder   llc;
  l1d_scoreboard  scb;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    agent = l1d_agent::type_id::create("agent", this);
    llc   = llc_responder::type_id::create("llc", this);
    scb   = l1d_scoreboard::type_id::create("scb", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    super.connect_phase(phase);
    // Connect monitor analysis ports to scoreboard
    agent.mon.req_ap.connect(scb.req_export);
    agent.mon.comp_ap.connect(scb.comp_export);
  endfunction

endclass
