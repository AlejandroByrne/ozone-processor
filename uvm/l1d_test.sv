`timescale 1ns/1ps

class l1d_base_test extends uvm_test;
  `uvm_component_utils(l1d_base_test)

  l1d_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = l1d_env::type_id::create("env", this);
  endfunction

  function void start_of_simulation_phase(uvm_phase phase);
    super.start_of_simulation_phase(phase);
    l1d_model_reset();
  endfunction

  task run_phase(uvm_phase phase);
    // Base test does nothing. Derived tests run sequences.
  endtask
endclass

// ── Individual test classes ──

class l1d_cold_load_test extends l1d_base_test;
  `uvm_component_utils(l1d_cold_load_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    l1d_cold_load_seq seq;
    phase.raise_objection(this);
    `uvm_info("TEST", "Starting Cold Load Test", UVM_LOW)
    seq = l1d_cold_load_seq::type_id::create("seq");
    seq.start(env.agent.sqr);
    #5000;
    phase.drop_objection(this);
  endtask
endclass

class l1d_raw_test extends l1d_base_test;
  `uvm_component_utils(l1d_raw_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    l1d_raw_seq seq;
    phase.raise_objection(this);
    `uvm_info("TEST", "Starting RAW Hazard Test", UVM_LOW)
    seq = l1d_raw_seq::type_id::create("seq");
    seq.start(env.agent.sqr);
    #5000;
    phase.drop_objection(this);
  endtask
endclass

class l1d_waw_test extends l1d_base_test;
  `uvm_component_utils(l1d_waw_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    l1d_waw_seq seq;
    phase.raise_objection(this);
    `uvm_info("TEST", "Starting WAW Hazard Test", UVM_LOW)
    seq = l1d_waw_seq::type_id::create("seq");
    seq.start(env.agent.sqr);
    #5000;
    phase.drop_objection(this);
  endtask
endclass

class l1d_mshr_exhaust_test extends l1d_base_test;
  `uvm_component_utils(l1d_mshr_exhaust_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    l1d_mshr_exhaust_seq seq;
    phase.raise_objection(this);
    `uvm_info("TEST", "Starting MSHR Exhaustion Test", UVM_LOW)
    seq = l1d_mshr_exhaust_seq::type_id::create("seq");
    seq.start(env.agent.sqr);
    #5000;
    phase.drop_objection(this);
  endtask
endclass

class l1d_secondary_miss_test extends l1d_base_test;
  `uvm_component_utils(l1d_secondary_miss_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    l1d_secondary_miss_seq seq;
    phase.raise_objection(this);
    `uvm_info("TEST", "Starting Secondary Miss Coalescing Test", UVM_LOW)
    seq = l1d_secondary_miss_seq::type_id::create("seq");
    seq.start(env.agent.sqr);
    #5000;
    phase.drop_objection(this);
  endtask
endclass

class l1d_set_conflict_test extends l1d_base_test;
  `uvm_component_utils(l1d_set_conflict_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    l1d_set_conflict_seq seq;
    phase.raise_objection(this);
    `uvm_info("TEST", "Starting Set Conflict / Eviction Test", UVM_LOW)
    seq = l1d_set_conflict_seq::type_id::create("seq");
    seq.start(env.agent.sqr);
    #10000;
    phase.drop_objection(this);
  endtask
endclass

class l1d_mshr_fwd_test extends l1d_base_test;
  `uvm_component_utils(l1d_mshr_fwd_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    l1d_mshr_fwd_seq seq;
    phase.raise_objection(this);
    `uvm_info("TEST", "Starting MSHR Forwarding Test", UVM_LOW)
    seq = l1d_mshr_fwd_seq::type_id::create("seq");
    seq.start(env.agent.sqr);
    #5000;
    phase.drop_objection(this);
  endtask
endclass

class l1d_mixed_random_test extends l1d_base_test;
  `uvm_component_utils(l1d_mixed_random_test)
  function new(string name, uvm_component parent); super.new(name, parent); endfunction
  task run_phase(uvm_phase phase);
    l1d_mixed_random_seq seq;
    phase.raise_objection(this);
    `uvm_info("TEST", "Starting Mixed Random Test (50 txns)", UVM_LOW)
    seq = l1d_mixed_random_seq::type_id::create("seq");
    seq.start(env.agent.sqr);
    #20000;
    phase.drop_objection(this);
  endtask
endclass
