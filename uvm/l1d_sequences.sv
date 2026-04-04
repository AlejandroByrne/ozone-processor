`timescale 1ns/1ps

// ============================================================
// Base sequence with tag allocator
// ============================================================
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

// ============================================================
// MSHR Exhaustion: 3 loads to different cache lines
// ============================================================
class l1d_mshr_exhaust_seq extends l1d_base_seq;
  `uvm_object_utils(l1d_mshr_exhaust_seq)

  function new(string name = "l1d_mshr_exhaust_seq");
    super.new(name);
    num_txns = 3;
  endfunction

  task body();
    l1d_item item;
    for (int i = 0; i < num_txns; i++) begin
      item = l1d_item::type_id::create($sformatf("mshr_ld_%0d", i));
      start_item(item);
      if (!item.randomize() with {
        is_write == 0;
        addr == i * 64;
      })
        `uvm_fatal("SEQ", "Randomization failed")
      item.tag = alloc_tag();
      finish_item(item);
    end
  endtask
endclass

// ============================================================
// Secondary Miss Coalescing: 4 loads to same cache line
// ============================================================
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
        addr == 64'h100 + (i * 8);  // same block, different words
      })
        `uvm_fatal("SEQ", "Randomization failed")
      item.tag = alloc_tag();
      finish_item(item);
    end
  endtask
endclass

// ============================================================
// RAW Hazard: Store then Load to same address
// ============================================================
class l1d_raw_seq extends l1d_base_seq;
  `uvm_object_utils(l1d_raw_seq)

  function new(string name = "l1d_raw_seq");
    super.new(name);
  endfunction

  task body();
    l1d_item store_item, load_item;
    bit [63:0] target_addr = 64'h200;

    store_item = l1d_item::type_id::create("raw_st");
    start_item(store_item);
    if (!store_item.randomize() with { is_write == 1; addr == target_addr; })
      `uvm_fatal("SEQ", "Randomization failed")
    store_item.tag = alloc_tag();
    finish_item(store_item);

    load_item = l1d_item::type_id::create("raw_ld");
    start_item(load_item);
    if (!load_item.randomize() with { is_write == 0; addr == target_addr; })
      `uvm_fatal("SEQ", "Randomization failed")
    load_item.tag = alloc_tag();
    finish_item(load_item);
  endtask
endclass

// ============================================================
// WAW Hazard: Two stores then load to same address
// ============================================================
class l1d_waw_seq extends l1d_base_seq;
  `uvm_object_utils(l1d_waw_seq)

  function new(string name = "l1d_waw_seq");
    super.new(name);
  endfunction

  task body();
    l1d_item st1, st2, ld;
    bit [63:0] target_addr = 64'h300;

    st1 = l1d_item::type_id::create("waw_st1");
    start_item(st1);
    if (!st1.randomize() with { is_write == 1; addr == target_addr; })
      `uvm_fatal("SEQ", "Randomization failed")
    st1.tag = alloc_tag();
    finish_item(st1);

    st2 = l1d_item::type_id::create("waw_st2");
    start_item(st2);
    if (!st2.randomize() with { is_write == 1; addr == target_addr; })
      `uvm_fatal("SEQ", "Randomization failed")
    st2.tag = alloc_tag();
    finish_item(st2);

    ld = l1d_item::type_id::create("waw_ld");
    start_item(ld);
    if (!ld.randomize() with { is_write == 0; addr == target_addr; })
      `uvm_fatal("SEQ", "Randomization failed")
    ld.tag = alloc_tag();
    finish_item(ld);
  endtask
endclass

// ============================================================
// Set Conflict: Force evictions by filling a set (>3 ways)
// ============================================================
class l1d_set_conflict_seq extends l1d_base_seq;
  `uvm_object_utils(l1d_set_conflict_seq)

  function new(string name = "l1d_set_conflict_seq");
    super.new(name);
  endfunction

  task body();
    l1d_item item;
    // 4 different tags mapping to set 0: addresses 0x000, 0x200, 0x400, 0x600
    // Set index bits are [8:6]. Set 0 = addr[8:6]==0.
    // Tag bits are [21:9]. So incrementing addr by 0x200 (bit 9) changes the tag.
    // First 3 fill all ways, 4th forces eviction.
    for (int i = 0; i < 4; i++) begin
      bit [63:0] a = 64'(i * 22'h200);

      // Store to populate
      item = l1d_item::type_id::create($sformatf("setc_st_%0d", i));
      start_item(item);
      if (!item.randomize() with { is_write == 1; addr == a; })
        `uvm_fatal("SEQ", "Randomization failed")
      item.tag = alloc_tag();
      finish_item(item);
    end

    // Now load back the first address — it should have been evicted
    item = l1d_item::type_id::create("setc_ld_evicted");
    start_item(item);
    if (!item.randomize() with { is_write == 0; addr == 64'h0; })
      `uvm_fatal("SEQ", "Randomization failed")
    item.tag = alloc_tag();
    finish_item(item);
  endtask
endclass

// ============================================================
// Store-to-Load MSHR Forwarding: store and load both miss
// ============================================================
class l1d_mshr_fwd_seq extends l1d_base_seq;
  `uvm_object_utils(l1d_mshr_fwd_seq)

  function new(string name = "l1d_mshr_fwd_seq");
    super.new(name);
  endfunction

  task body();
    l1d_item st, ld;
    bit [63:0] target_addr = 64'h400;

    // Store misses (cold cache)
    st = l1d_item::type_id::create("fwd_st");
    start_item(st);
    if (!st.randomize() with { is_write == 1; addr == target_addr; })
      `uvm_fatal("SEQ", "Randomization failed")
    st.tag = alloc_tag();
    finish_item(st);

    // Load to same address — should forward from MSHR
    ld = l1d_item::type_id::create("fwd_ld");
    start_item(ld);
    if (!ld.randomize() with { is_write == 0; addr == target_addr; })
      `uvm_fatal("SEQ", "Randomization failed")
    ld.tag = alloc_tag();
    finish_item(ld);
  endtask
endclass

// ============================================================
// Mixed Random: many random transactions
// ============================================================
class l1d_mixed_random_seq extends l1d_base_seq;
  `uvm_object_utils(l1d_mixed_random_seq)

  function new(string name = "l1d_mixed_random_seq");
    super.new(name);
    num_txns = 50;
  endfunction

  // Use default body() — fully random within constraints
endclass

// ============================================================
// Cold Cache Load: verify uninitialized reads return address-as-data
// ============================================================
class l1d_cold_load_seq extends l1d_base_seq;
  `uvm_object_utils(l1d_cold_load_seq)

  function new(string name = "l1d_cold_load_seq");
    super.new(name);
  endfunction

  task body();
    l1d_item item;
    // Load from several addresses that were never stored to
    for (int i = 0; i < 8; i++) begin
      item = l1d_item::type_id::create($sformatf("cold_ld_%0d", i));
      start_item(item);
      if (!item.randomize() with {
        is_write == 0;
        addr == 64'(i * 8 + 64'h1000);
      })
        `uvm_fatal("SEQ", "Randomization failed")
      item.tag = alloc_tag();
      finish_item(item);
    end
  endtask
endclass
