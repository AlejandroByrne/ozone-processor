`timescale 1ns/1ps
// ═══════════════════════════════════════════════════════════════
//  Base sequence — single transaction with auto-incrementing tags
// ═══════════════════════════════════════════════════════════════
class lsu_base_seq extends uvm_sequence #(lsu_seq_item);
  `uvm_object_utils(lsu_base_seq)

  int unsigned num_txns = 10;
  static bit [9:0] next_tag = 0;

  function new(string name = "lsu_base_seq");
    super.new(name);
  endfunction

  function bit [9:0] alloc_tag();
    bit [9:0] t = next_tag;
    next_tag++;
    return t;
  endfunction

  task body();
    lsu_seq_item item;
    for (int i = 0; i < num_txns; i++) begin
      item = lsu_seq_item::type_id::create($sformatf("item_%0d", i));
      start_item(item);
      if (!item.randomize())
        `uvm_fatal("SEQ", "Randomization failed")
      item.tag = alloc_tag();
      finish_item(item);
    end
  endtask
endclass


// ═══════════════════════════════════════════════════════════════
//  Load-only sequence
// ═══════════════════════════════════════════════════════════════
class lsu_load_only_seq extends lsu_base_seq;
  `uvm_object_utils(lsu_load_only_seq)

  function new(string name = "lsu_load_only_seq");
    super.new(name);
  endfunction

  task body();
    lsu_seq_item item;
    for (int i = 0; i < num_txns; i++) begin
      item = lsu_seq_item::type_id::create($sformatf("load_%0d", i));
      start_item(item);
      if (!item.randomize() with { is_write == 0; })
        `uvm_fatal("SEQ", "Randomization failed")
      item.tag = alloc_tag();
      finish_item(item);
    end
  endtask
endclass


// ═══════════════════════════════════════════════════════════════
//  Store-only sequence
// ═══════════════════════════════════════════════════════════════
class lsu_store_only_seq extends lsu_base_seq;
  `uvm_object_utils(lsu_store_only_seq)

  function new(string name = "lsu_store_only_seq");
    super.new(name);
  endfunction

  task body();
    lsu_seq_item item;
    for (int i = 0; i < num_txns; i++) begin
      item = lsu_seq_item::type_id::create($sformatf("store_%0d", i));
      start_item(item);
      if (!item.randomize() with { is_write == 1; })
        `uvm_fatal("SEQ", "Randomization failed")
      item.tag = alloc_tag();
      finish_item(item);
    end
  endtask
endclass


// ═══════════════════════════════════════════════════════════════
//  RAW hazard: store to address A, then load from address A
// ═══════════════════════════════════════════════════════════════
class lsu_raw_hazard_seq extends lsu_base_seq;
  `uvm_object_utils(lsu_raw_hazard_seq)

  function new(string name = "lsu_raw_hazard_seq");
    super.new(name);
  endfunction

  task body();
    lsu_seq_item store_item, load_item;

    for (int i = 0; i < num_txns / 2; i++) begin
      bit [63:0] target_addr;

      // Randomize a target address
      store_item = lsu_seq_item::type_id::create($sformatf("raw_st_%0d", i));
      start_item(store_item);
      if (!store_item.randomize() with { is_write == 1; })
        `uvm_fatal("SEQ", "Randomization failed")
      store_item.tag = alloc_tag();
      target_addr = store_item.addr;
      finish_item(store_item);

      // Load from same address
      load_item = lsu_seq_item::type_id::create($sformatf("raw_ld_%0d", i));
      start_item(load_item);
      if (!load_item.randomize() with {
        is_write == 0;
        addr == target_addr;
      })
        `uvm_fatal("SEQ", "Randomization failed")
      load_item.tag = alloc_tag();
      finish_item(load_item);
    end
  endtask
endclass


// ═══════════════════════════════════════════════════════════════
//  WAW hazard: two stores to the same address, then a load
// ═══════════════════════════════════════════════════════════════
class lsu_waw_hazard_seq extends lsu_base_seq;
  `uvm_object_utils(lsu_waw_hazard_seq)

  function new(string name = "lsu_waw_hazard_seq");
    super.new(name);
  endfunction

  task body();
    lsu_seq_item st1, st2, ld;

    for (int i = 0; i < num_txns / 3; i++) begin
      bit [63:0] target_addr;
      bit [63:0] final_value;

      // First store
      st1 = lsu_seq_item::type_id::create($sformatf("waw_st1_%0d", i));
      start_item(st1);
      if (!st1.randomize() with { is_write == 1; })
        `uvm_fatal("SEQ", "Randomization failed")
      st1.tag = alloc_tag();
      target_addr = st1.addr;
      finish_item(st1);

      // Second store to same address (overwrites)
      st2 = lsu_seq_item::type_id::create($sformatf("waw_st2_%0d", i));
      start_item(st2);
      if (!st2.randomize() with {
        is_write == 1;
        addr == target_addr;
      })
        `uvm_fatal("SEQ", "Randomization failed")
      st2.tag = alloc_tag();
      final_value = st2.value;
      finish_item(st2);

      // Load — should return the second store's value
      ld = lsu_seq_item::type_id::create($sformatf("waw_ld_%0d", i));
      start_item(ld);
      if (!ld.randomize() with {
        is_write == 0;
        addr == target_addr;
      })
        `uvm_fatal("SEQ", "Randomization failed")
      ld.tag = alloc_tag();
      finish_item(ld);
    end
  endtask
endclass


// ═══════════════════════════════════════════════════════════════
//  Set conflict: multiple accesses to different blocks in the
//  same cache set, forcing evictions (L1D is 3-way, 8 sets)
// ═══════════════════════════════════════════════════════════════
class lsu_set_conflict_seq extends lsu_base_seq;
  `uvm_object_utils(lsu_set_conflict_seq)

  function new(string name = "lsu_set_conflict_seq");
    super.new(name);
  endfunction

  task body();
    lsu_seq_item item;
    // Target set 0: addr[8:6] = 0.  Hit 5 different tags → forces
    // evictions in a 3-way cache (ways 0,1,2 fill, then 3,4 evict)
    for (int tag_idx = 0; tag_idx < 5; tag_idx++) begin
      bit [63:0] target_addr = {42'b0, tag_idx[12:0], 3'b000, 6'b0};  // set=0, varying tag

      // Store
      item = lsu_seq_item::type_id::create($sformatf("conflict_st_%0d", tag_idx));
      start_item(item);
      if (!item.randomize() with {
        is_write == 1;
        addr == target_addr;
      })
        `uvm_fatal("SEQ", "Randomization failed")
      item.tag = alloc_tag();
      finish_item(item);

      // Load back
      item = lsu_seq_item::type_id::create($sformatf("conflict_ld_%0d", tag_idx));
      start_item(item);
      if (!item.randomize() with {
        is_write == 0;
        addr == target_addr;
      })
        `uvm_fatal("SEQ", "Randomization failed")
      item.tag = alloc_tag();
      finish_item(item);
    end
  endtask
endclass


// ═══════════════════════════════════════════════════════════════
//  Stress: back-to-back transactions with zero delay,
//  designed to fill the LSU queue (QUEUE_DEPTH=8)
// ═══════════════════════════════════════════════════════════════
class lsu_stress_seq extends lsu_base_seq;
  `uvm_object_utils(lsu_stress_seq)

  function new(string name = "lsu_stress_seq");
    super.new(name);
    num_txns = 32;
  endfunction

  task body();
    lsu_seq_item item;
    for (int i = 0; i < num_txns; i++) begin
      item = lsu_seq_item::type_id::create($sformatf("stress_%0d", i));
      start_item(item);
      if (!item.randomize() with {
        inter_phase_delay == 0;
      })
        `uvm_fatal("SEQ", "Randomization failed")
      item.tag = alloc_tag();
      finish_item(item);
    end
  endtask
endclass


// ═══════════════════════════════════════════════════════════════
//  Mixed random: unconstrained, maximum state space exploration
// ═══════════════════════════════════════════════════════════════
class lsu_mixed_random_seq extends lsu_base_seq;
  `uvm_object_utils(lsu_mixed_random_seq)

  function new(string name = "lsu_mixed_random_seq");
    super.new(name);
    num_txns = 50;
  endfunction

  task body();
    lsu_seq_item item;
    for (int i = 0; i < num_txns; i++) begin
      item = lsu_seq_item::type_id::create($sformatf("mixed_%0d", i));
      start_item(item);
      if (!item.randomize())
        `uvm_fatal("SEQ", "Randomization failed")
      item.tag = alloc_tag();
      finish_item(item);
    end
  endtask
endclass
