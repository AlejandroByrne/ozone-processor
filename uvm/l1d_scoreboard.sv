`timescale 1ns/1ps

`uvm_analysis_imp_decl(_req)
`uvm_analysis_imp_decl(_comp)
`uvm_analysis_imp_decl(_fill)

class l1d_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(l1d_scoreboard)

  uvm_analysis_imp_req  #(l1d_item, l1d_scoreboard)     req_export;
  uvm_analysis_imp_comp #(l1d_item, l1d_scoreboard)     comp_export;
  uvm_analysis_imp_fill #(l1d_llc_item, l1d_scoreboard) fill_export;

  // Expected completions indexed by processor tag
  typedef struct {
    bit [63:0] data;
    bit        is_write;
    bit        valid;
  } expected_t;

  expected_t expected[int];   // tag -> expected completion
  int pending_tags[$];        // ordered list of issued but uncompleted tags

  // Buffer for early completions (DUT completion arrived before fill event)
  typedef struct {
    int        tag;
    bit [63:0] value;
    bit        is_write;
  } early_comp_t;

  early_comp_t early_comps[$];

  int num_checks;
  int num_write_comps;
  int num_errors;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    req_export  = new("req_export", this);
    comp_export = new("comp_export", this);
    fill_export = new("fill_export", this);
    num_checks = 0;
    num_write_comps = 0;
    num_errors = 0;
  endfunction

  // Drain all queued completions from the golden model into expected map
  function void drain_model_completions();
    int    t;
    longint d;
    int    w;
    while (l1d_model_pop_completion(t, d, w)) begin
      expected_t e;
      e.data     = d;
      e.is_write = w;
      e.valid    = 1;
      expected[t] = e;
      `uvm_info("SCB", $sformatf("EXPECT: tag=%0d data=0x%0h write=%0b", t, d, w), UVM_HIGH)
    end
  endfunction

  // Check a single completion against expectations
  function void check_completion(int t, bit [63:0] comp_value, bit comp_is_write);
    if (!expected.exists(t)) begin
      `uvm_warning("SCB", $sformatf("COMP tag=%0d: still no expectation after retrying", t))
      return;
    end

    begin
    expected_t e;
    e = expected[t];

    if (e.is_write) begin
      `uvm_info("SCB", $sformatf("WRITE COMP OK: tag=%0d", t), UVM_LOW)
      num_write_comps++;
    end else begin
      if (comp_value !== e.data) begin
        `uvm_error("SCB", $sformatf(
          "DATA MISMATCH tag=%0d expected=0x%0h actual=0x%0h",
          t, e.data, comp_value))
        num_errors++;
      end else begin
        `uvm_info("SCB", $sformatf("LOAD OK: tag=%0d data=0x%0h", t, e.data), UVM_LOW)
        num_checks++;
      end
    end

    expected.delete(t);
    end
  endfunction

  // Try to resolve buffered early completions against expectations
  function void resolve_early_completions();
    early_comp_t remaining[$];
    foreach (early_comps[i]) begin
      if (expected.exists(early_comps[i].tag)) begin
        check_completion(early_comps[i].tag, early_comps[i].value, early_comps[i].is_write);
      end else begin
        remaining.push_back(early_comps[i]);
      end
    end
    early_comps = remaining;
  endfunction

  // -- Request from LSU accepted by DUT --
  virtual function void write_req(l1d_item item);
    int result;
    result = l1d_model_request(
      int'(item.addr[21:0]),
      longint'(item.value),
      int'(item.tag),
      int'(item.is_write)
    );

    pending_tags.push_back(int'(item.tag));

    if (result) begin
      drain_model_completions();
    end

    `uvm_info("SCB", $sformatf("REQ: %s tag=%0d addr=0x%0h -> %s",
              item.is_write ? "ST" : "LD", item.tag, item.addr,
              result ? "HIT/FWD" : "MISS"), UVM_HIGH)
  endfunction

  // -- LLC fill accepted by DUT --
  virtual function void write_fill(l1d_llc_item item);
    int n;
    int block_addr = int'(item.addr[21:6]);

    n = l1d_model_fill(block_addr,
      longint'(item.words[0]), longint'(item.words[1]),
      longint'(item.words[2]), longint'(item.words[3]),
      longint'(item.words[4]), longint'(item.words[5]),
      longint'(item.words[6]), longint'(item.words[7])
    );

    drain_model_completions();

    // Now try to match any early completions that were buffered
    resolve_early_completions();

    `uvm_info("SCB", $sformatf("FILL: addr=0x%0h -> %0d completions", item.addr, n), UVM_HIGH)
  endfunction

  // -- Completion from DUT --
  virtual function void write_comp(l1d_item item);
    int t = int'(item.tag);

    if (!expected.exists(t)) begin
      // Buffer it — fill event may arrive later due to monitor timing
      early_comp_t ec;
      ec.tag = t;
      ec.value = item.completion_value;
      ec.is_write = item.is_write;
      early_comps.push_back(ec);
      `uvm_info("SCB", $sformatf("COMP tag=%0d: buffered (awaiting fill)", t), UVM_HIGH)
      return;
    end

    check_completion(t, item.completion_value, item.is_write);

    // Remove from pending list
    foreach (pending_tags[i]) begin
      if (pending_tags[i] == t) begin
        pending_tags.delete(i);
        break;
      end
    end
  endfunction

  virtual function void report_phase(uvm_phase phase);
    int remaining = l1d_model_pending_count();

    // Try one last time to resolve early completions
    resolve_early_completions();

    if (early_comps.size() > 0) begin
      `uvm_warning("SCB", $sformatf("%0d early completions never matched", early_comps.size()))
      foreach (early_comps[i])
        `uvm_info("SCB", $sformatf("  unmatched early: tag=%0d", early_comps[i].tag), UVM_LOW)
    end

    if (expected.num() > 0) begin
      `uvm_warning("SCB", $sformatf("%0d expected completions never received from DUT", expected.num()))
      foreach (expected[t])
        `uvm_info("SCB", $sformatf("  unreceived: tag=%0d write=%0b", t, expected[t].is_write), UVM_LOW)
    end

    if (num_errors > 0)
      `uvm_error("SCB", $sformatf("TEST FAILED -- %0d data mismatches", num_errors))
    else
      `uvm_info("SCB", $sformatf(
        "TEST PASSED -- %0d loads checked, %0d store completions, %0d unreceived",
        num_checks, num_write_comps, expected.num()), UVM_LOW)
  endfunction
endclass
