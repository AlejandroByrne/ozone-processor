// ═══════════════════════════════════════════════════════════════
//  Base test — builds the environment, configures timeout
// ═══════════════════════════════════════════════════════════════
class lsu_base_test extends uvm_test;
  `uvm_component_utils(lsu_base_test)

  lsu_l1d_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = lsu_l1d_env::type_id::create("env", this);
  endfunction

  function void end_of_elaboration_phase(uvm_phase phase);
    super.end_of_elaboration_phase(phase);
    uvm_top.print_topology();
  endfunction

  task run_phase(uvm_phase phase);
    lsu_base_seq seq;
    phase.raise_objection(this);

    seq = lsu_base_seq::type_id::create("seq");
    seq.num_txns = 10;
    seq.start(env.agent.sqr);

    // Drain time — allow completions to return
    #2000;

    phase.drop_objection(this);
  endtask
endclass


// ═══════════════════════════════════════════════════════════════
//  Load-only test
// ═══════════════════════════════════════════════════════════════
class lsu_load_test extends lsu_base_test;
  `uvm_component_utils(lsu_load_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    lsu_load_only_seq seq;
    phase.raise_objection(this);

    seq = lsu_load_only_seq::type_id::create("seq");
    seq.num_txns = 20;
    seq.start(env.agent.sqr);
    #5000;

    phase.drop_objection(this);
  endtask
endclass


// ═══════════════════════════════════════════════════════════════
//  Store-only test
// ═══════════════════════════════════════════════════════════════
class lsu_store_test extends lsu_base_test;
  `uvm_component_utils(lsu_store_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    lsu_store_only_seq seq;
    phase.raise_objection(this);

    seq = lsu_store_only_seq::type_id::create("seq");
    seq.num_txns = 20;
    seq.start(env.agent.sqr);
    #5000;

    phase.drop_objection(this);
  endtask
endclass


// ═══════════════════════════════════════════════════════════════
//  RAW hazard test — store then load to same address
// ═══════════════════════════════════════════════════════════════
class lsu_raw_test extends lsu_base_test;
  `uvm_component_utils(lsu_raw_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    lsu_raw_hazard_seq seq;
    phase.raise_objection(this);

    seq = lsu_raw_hazard_seq::type_id::create("seq");
    seq.num_txns = 20;
    seq.start(env.agent.sqr);
    #10000;

    phase.drop_objection(this);
  endtask
endclass


// ═══════════════════════════════════════════════════════════════
//  WAW hazard test — two stores then load to same address
// ═══════════════════════════════════════════════════════════════
class lsu_waw_test extends lsu_base_test;
  `uvm_component_utils(lsu_waw_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    lsu_waw_hazard_seq seq;
    phase.raise_objection(this);

    seq = lsu_waw_hazard_seq::type_id::create("seq");
    seq.num_txns = 15;
    seq.start(env.agent.sqr);
    #10000;

    phase.drop_objection(this);
  endtask
endclass


// ═══════════════════════════════════════════════════════════════
//  Cache set conflict test — force evictions
// ═══════════════════════════════════════════════════════════════
class lsu_eviction_test extends lsu_base_test;
  `uvm_component_utils(lsu_eviction_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    lsu_set_conflict_seq seq;
    phase.raise_objection(this);

    seq = lsu_set_conflict_seq::type_id::create("seq");
    seq.start(env.agent.sqr);
    #20000;

    phase.drop_objection(this);
  endtask
endclass


// ═══════════════════════════════════════════════════════════════
//  Stress test — back-to-back, fill the queue
// ═══════════════════════════════════════════════════════════════
class lsu_stress_test extends lsu_base_test;
  `uvm_component_utils(lsu_stress_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    lsu_stress_seq seq;
    phase.raise_objection(this);

    seq = lsu_stress_seq::type_id::create("seq");
    seq.start(env.agent.sqr);
    #20000;

    phase.drop_objection(this);
  endtask
endclass


// ═══════════════════════════════════════════════════════════════
//  Full random regression test
// ═══════════════════════════════════════════════════════════════
class lsu_random_test extends lsu_base_test;
  `uvm_component_utils(lsu_random_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    lsu_mixed_random_seq seq;
    phase.raise_objection(this);

    seq = lsu_mixed_random_seq::type_id::create("seq");
    seq.num_txns = 100;
    seq.start(env.agent.sqr);
    #30000;

    phase.drop_objection(this);
  endtask
endclass
