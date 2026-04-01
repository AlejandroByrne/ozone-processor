// Self-checking scoreboard with reference memory model.
//
// Maintains an associative array of expected memory contents. On stores,
// updates the model. On load completions, compares the returned value
// against the model. Tracks pending loads for timeout detection.

// These macros define uvm_analysis_imp_req and uvm_analysis_imp_comp classes.
// They MUST be at package/compilation-unit scope, NOT inside a class.
`uvm_analysis_imp_decl(_req)
`uvm_analysis_imp_decl(_comp)

// DPI-C Golden Model Imports
import "DPI-C" function void mem_write(longint unsigned addr, longint unsigned data);
import "DPI-C" function longint unsigned mem_read(longint unsigned addr);
import "DPI-C" function void mem_reset();

class lsu_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(lsu_scoreboard)

  // TLM analysis exports — connected to the monitor's analysis ports
  uvm_analysis_imp_req  #(lsu_seq_item, lsu_scoreboard)  req_export;
  uvm_analysis_imp_comp #(lsu_seq_item, lsu_scoreboard)  comp_export;

  // Reference memory model: addr → value
  // Now managed in C++ via DPI
  // logic [63:0] ref_mem [logic [63:0]];

  // Pending loads: tag → expected value
  typedef struct {
    logic [63:0] addr;
    logic [63:0] expected_value;
    int          issue_time;
  } pending_load_t;

  pending_load_t pending_loads [bit [9:0]];

  // Counters
  int num_loads_checked  = 0;
  int num_stores_seen    = 0;
  int num_errors         = 0;
  int num_load_timeouts  = 0;

  // Timeout threshold (cycles)
  int unsigned load_timeout = 500;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    mem_reset(); // Initialize C++ model
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    req_export  = new("req_export", this);
    comp_export = new("comp_export", this);
  endfunction

  // ── Called by monitor when a request (load or store) enters the LSU ──
  function void write_req(lsu_seq_item item);
    if (item.is_write) begin
      // Store: update reference model in C++
      mem_write(item.addr, item.value);
      num_stores_seen++;
      `uvm_info("SCB", $sformatf("STORE: ref_mem[0x%0h] = 0x%0h (tag=%0d)",
                item.addr, item.value, item.tag), UVM_HIGH)
    end else begin
      // Load: record expected value from C++ reference model
      pending_load_t pl;
      pl.addr           = item.addr;
      pl.expected_value  = mem_read(item.addr);
      pl.issue_time      = $stime;
      pending_loads[item.tag] = pl;
      `uvm_info("SCB", $sformatf("LOAD: expecting ref_mem[0x%0h] = 0x%0h (tag=%0d)",
                item.addr, pl.expected_value, item.tag), UVM_HIGH)
    end
  endfunction

  // ── Called by monitor when a completion comes back from the LSU ──
  function void write_comp(lsu_seq_item item);
    bit [9:0] t = item.tag;

    if (!pending_loads.exists(t)) begin
      // Could be a store completion — not an error
      `uvm_info("SCB", $sformatf("Completion for tag=%0d (not a pending load, possibly store ack)",
                t), UVM_HIGH)
      return;
    end

    // Compare returned value against reference model
    pending_load_t pl = pending_loads[t];
    pending_loads.delete(t);
    num_loads_checked++;

    if (item.completion_value !== pl.expected_value) begin
      num_errors++;
      `uvm_error("SCB", $sformatf(
        "MISMATCH tag=%0d addr=0x%0h: got=0x%0h expected=0x%0h",
        t, pl.addr, item.completion_value, pl.expected_value))
    end else begin
      `uvm_info("SCB", $sformatf(
        "MATCH tag=%0d addr=0x%0h value=0x%0h",
        t, pl.addr, item.completion_value), UVM_MEDIUM)
    end
  endfunction

  // ── End-of-test checks ──
  function void check_phase(uvm_phase phase);
    super.check_phase(phase);

    // Flag any loads that never completed
    foreach (pending_loads[t]) begin
      num_load_timeouts++;
      `uvm_error("SCB", $sformatf("TIMEOUT: load tag=%0d addr=0x%0h never completed",
                 t, pending_loads[t].addr))
    end
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);
    `uvm_info("SCB", $sformatf(
      "\n══════════════════════════════\n" +
      "  Scoreboard Summary\n" +
      "  Stores seen:      %0d\n" +
      "  Loads checked:    %0d\n" +
      "  Load mismatches:  %0d\n" +
      "  Load timeouts:    %0d\n" +
      "══════════════════════════════",
      num_stores_seen, num_loads_checked, num_errors, num_load_timeouts), UVM_LOW)

    if (num_errors > 0 || num_load_timeouts > 0)
      `uvm_error("SCB", "TEST FAILED — see above errors")
    else if (num_loads_checked == 0)
      `uvm_warning("SCB", "No loads were checked — test may be vacuous")
    else
      `uvm_info("SCB", "TEST PASSED", UVM_LOW)
  endfunction

endclass
