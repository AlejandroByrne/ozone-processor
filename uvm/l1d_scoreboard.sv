`timescale 1ns/1ps

`uvm_analysis_imp_decl(_req)
`uvm_analysis_imp_decl(_comp)

class l1d_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(l1d_scoreboard)

  // Inboxes from the Monitor
  uvm_analysis_imp_req #(l1d_item, l1d_scoreboard) req_export;
  uvm_analysis_imp_comp #(l1d_item, l1d_scoreboard) comp_export;

  // --- Verification State ---
  
  // Tracks expected values for specific tags (only for initialized addresses)
  bit [63:0] expected_reads[int];
  
  // Tracks whether a specific tag should have its data checked or not
  bit check_data_for_tag[int];

  // Tracks which addresses have been written to at least once
  // Key: 8-byte aligned address
  bit address_initialized[bit [63:0]];

  int num_loads_checked;
  int num_uninitialized_loads;
  int num_errors;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    req_export  = new("req_export", this);
    comp_export = new("comp_export", this);
    num_loads_checked = 0;
    num_uninitialized_loads = 0;
    num_errors = 0;
  endfunction

  // ── Called when Monitor sees a request start ──
  virtual function void write_req(l1d_item item);
    bit [63:0] aligned_addr = item.addr & ~64'h7;

    if (item.is_write) begin
      // 1. Mark this address as initialized
      address_initialized[aligned_addr] = 1;
      // 2. Update the C++ Golden Model
      mem_write(item.addr, item.value);
      `uvm_info("SCB", $sformatf("STORE REQ: addr=0x%0h. Address marked initialized.", aligned_addr), UVM_HIGH)
    end else begin
      // 3. For LOADS, decide if we care about the data
      if (address_initialized.exists(aligned_addr)) begin
        // Address was written before. We expect a specific value.
        check_data_for_tag[item.tag] = 1;
        expected_reads[item.tag]     = mem_read(item.addr);
        `uvm_info("SCB", $sformatf("LOAD REQ (Init): tag=%0d addr=0x%0h. Data will be verified.", item.tag, aligned_addr), UVM_HIGH)
      end else begin
        // Address never written. Design decision: Skip data check.
        check_data_for_tag[item.tag] = 0;
        `uvm_info("SCB", $sformatf("LOAD REQ (Uninit): tag=%0d addr=0x%0h. Data verification skipped.", item.tag, aligned_addr), UVM_HIGH)
      end
    end
  endfunction

  // ── Called when Monitor sees a completion finish ──
  virtual function void write_comp(l1d_item item);
    // If the tag isn't in our 'check' map, it might be a Store completion
    // (Stores don't put entries in check_data_for_tag in this simplified SCB)
    if (!check_data_for_tag.exists(item.tag)) begin
      `uvm_info("SCB", $sformatf("COMPLETION: tag=%0d (Likely STORE or Internal Op)", item.tag), UVM_HIGH)
      return;
    end

    if (check_data_for_tag[item.tag] == 1) begin
      // DATA VERIFICATION REQUIRED
      if (!expected_reads.exists(item.tag)) begin
        `uvm_error("SCB", $sformatf("Bug in Scoreboard: Tag %0d marked for check but no expected value found", item.tag))
      end else begin
        bit [63:0] exp_val = expected_reads[item.tag];
        if (item.completion_value !== exp_val) begin
          `uvm_error("SCB", $sformatf("DATA MISMATCH tag=%0d expected=0x%0h actual=0x%0h", item.tag, exp_val, item.completion_value))
          num_errors++;
        end else begin
          `uvm_info("SCB", $sformatf("DATA MATCH tag=%0d value=0x%0h", item.tag, exp_val), UVM_LOW)
          num_loads_checked++;
        end
        expected_reads.delete(item.tag);
      end
    end else begin
      // DATA VERIFICATION SKIPPED (Uninitialized memory)
      `uvm_info("SCB", $sformatf("PROTOCOL MATCH tag=%0d. Data check skipped (uninitialized addr).", item.tag), UVM_LOW)
      num_uninitialized_loads++;
    end

    // Cleanup
    check_data_for_tag.delete(item.tag);
  endfunction

  virtual function void report_phase(uvm_phase phase);
    if (num_errors > 0)
      `uvm_fatal("SCB", "TEST FAILED -- see above data mismatches")
    else
      `uvm_info("SCB", $sformatf("TEST PASSED (%0d checked, %0d skipped)", num_loads_checked, num_uninitialized_loads), UVM_LOW)
  endfunction

endclass
