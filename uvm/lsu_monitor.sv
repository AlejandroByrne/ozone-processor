`timescale 1ns/1ps
class lsu_monitor extends uvm_monitor;
  `uvm_component_utils(lsu_monitor)

  virtual lsu_proc_if vif;

  // To send to the soreboard:
  // Analysis ports: one for requests entering the LSU, one for completions leaving
  uvm_analysis_port #(lsu_seq_item) req_ap;
  uvm_analysis_port #(lsu_seq_item) comp_ap;

  // Pending instruction phases, keyed by tag — waiting for their data phase
  lsu_seq_item pending_instrs[bit [9:0]];

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    req_ap  = new("req_ap", this);
    comp_ap = new("comp_ap", this);
    if (!uvm_config_db#(virtual lsu_proc_if)::get(this, "", "proc_vif", vif))
      `uvm_fatal("NOVIF", "Could not get proc_vif from config_db")
  endfunction

  task run_phase(uvm_phase phase);
    fork
      monitor_requests();
      monitor_completions();
    join
  endtask

  // ── Watch the two-phase dispatch protocol ──
  //
  //  Correlates instruction phase (tag + op type) with data phase (tag + addr + value)
  //  by matching tags. When both phases are captured, a complete transaction is
  //  written to req_ap for the scoreboard.
  //
  task monitor_requests();
    forever begin
      @(posedge vif.clk);

      // Capture instruction phase (valid & ready handshake)
      if (vif.proc_instr_valid && vif.proc_instr_ready) begin
        lsu_seq_item item = lsu_seq_item::type_id::create("req_item");
        item.tag      = vif.proc_instr_tag;
        item.is_write = vif.proc_instr_is_write;
        pending_instrs[item.tag] = item;
        `uvm_info("MON", $sformatf("INSTR phase: %s tag=%0d",
                  item.is_write ? "STORE" : "LOAD", item.tag), UVM_HIGH)
      end

      // Capture data phase (valid & ready handshake)
      if (vif.proc_data_valid && vif.proc_data_ready) begin
        bit [9:0] dtag = vif.proc_data_tag;
        if (pending_instrs.exists(dtag)) begin
          lsu_seq_item item = pending_instrs[dtag];
          item.addr  = vif.proc_addr;
          item.value = vif.proc_value;
          pending_instrs.delete(dtag);
          req_ap.write(item);
          `uvm_info("MON", $sformatf("REQ complete: %s", item.convert2string()), UVM_MEDIUM)
        end else begin
          `uvm_warning("MON", $sformatf("Data phase for unknown tag %0d", dtag))
        end
      end
    end
  endtask

  // ── Watch the completion port ──
  task monitor_completions();
    forever begin
      @(posedge vif.clk);
      if (vif.completion_valid) begin
        lsu_seq_item item = lsu_seq_item::type_id::create("comp_item");
        item.tag              = vif.completion_tag;
        item.completion_value = vif.completion_value;
        item.completion_received = 1;
        comp_ap.write(item);
        `uvm_info("MON", $sformatf("COMPLETION: tag=%0d value=0x%0h",
                  item.tag, item.completion_value), UVM_MEDIUM)
      end
    end
  endtask

endclass
