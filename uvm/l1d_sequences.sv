`timescale 1ns/1ps

class l1d_base_seq extends uvm_sequence #(l1d_item);
  `uvm_object_utils(l1d_base_seq)

  int unsigned num_txns = 10;
  static bit [9:0] next_tag = 0;

  function new(string name = "l1d_base_seq");
    super.new(name);
  endfunction

  function bit [9:0] alloc_tag();
    bit [9:0] t = next_tag;
    next_tag++;
    return t;
  endfunction

  task body();
    l1d_item item;
    for (int i = 0; i < num_txns; i++) begin
      item = l1d_item::type_id::create($sformatf("item_%0d", i));
      start_item(item);
      if (!item.randomize())
        `uvm_fatal("SEQ", "Randomization failed")
      item.tag = alloc_tag();
      finish_item(item);
    end
  endtask
endclass

// MSHR Exhaustion Test: Send multiple Load requests to DIFFERENT cache lines
class l1d_mshr_exhaust_seq extends l1d_base_seq;
  `uvm_object_utils(l1d_mshr_exhaust_seq)

  function new(string name = "l1d_mshr_exhaust_seq");
    super.new(name);
    num_txns = 3; // 2 to fill, 1 to overflow
  endfunction

  task body();
    l1d_item item;
    for (int i = 0; i < num_txns; i++) begin
      item = l1d_item::type_id::create($sformatf("mshr_ld_%0d", i));
      start_item(item);
      if (!item.randomize() with {
        is_write == 0;
        addr == i * 64; // Different cache lines
      })
        `uvm_fatal("SEQ", "Randomization failed")
      item.tag = alloc_tag();
      finish_item(item);
    end
  endtask
endclass

// Secondary Miss Coalescing Test: Send multiple Load requests to the SAME cache line
class l1d_secondary_miss_seq extends l1d_base_seq;
  `uvm_object_utils(l1d_secondary_miss_seq)

  function new(string name = "l1d_secondary_miss_seq");
    super.new(name);
    num_txns = 4; 
  endfunction

  task body();
    l1d_item item;
    for (int i = 0; i < num_txns; i++) begin
      item = l1d_item::type_id::create($sformatf("sec_miss_ld_%0d", i));
      start_item(item);
      if (!item.randomize() with {
        is_write == 0;
        addr == 64'h100; // Same cache line
      })
        `uvm_fatal("SEQ", "Randomization failed")
      item.tag = alloc_tag();
      finish_item(item);
    end
  endtask
endclass

// Write-then-Read (RAW) on same address
class l1d_raw_seq extends l1d_base_seq;
  `uvm_object_utils(l1d_raw_seq)

  function new(string name = "l1d_raw_seq");
    super.new(name);
  endfunction

  task body();
    l1d_item store_item, load_item;
    bit [63:0] target_addr = 64'h800;

    // Send the STORE
    store_item = l1d_item::type_id::create("raw_st");
    start_item(store_item);
    if (!store_item.randomize() with { is_write == 1; addr == target_addr; })
      `uvm_fatal("SEQ", "Randomization failed")
    store_item.tag = alloc_tag();
    finish_item(store_item);

    // Send the LOAD
    load_item = l1d_item::type_id::create("raw_ld");
    start_item(load_item);
    if (!load_item.randomize() with { is_write == 0; addr == target_addr; })
      `uvm_fatal("SEQ", "Randomization failed")
    load_item.tag = alloc_tag();
    finish_item(load_item);
  endtask
endclass
