`timescale 1ns/1ps
class lsu_driver extends uvm_driver #(lsu_seq_item);
  `uvm_component_utils(lsu_driver)

  virtual lsu_proc_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual lsu_proc_if)::get(this, "", "proc_vif", vif))
      `uvm_fatal("NOVIF", "Could not get proc_vif from config_db")
  endfunction

  task run_phase(uvm_phase phase);
    lsu_seq_item item;
    // Initialize outputs
    vif.proc_instr_valid  <= 1'b0;
    vif.proc_instr_tag    <= '0;
    vif.proc_instr_is_write <= 1'b0;
    vif.proc_data_valid   <= 1'b0;
    vif.proc_data_tag     <= '0;
    vif.proc_addr         <= '0;
    vif.proc_value        <= '0;

    // Wait for reset de-assertion
    @(posedge vif.rst_n);
    @(posedge vif.clk);

    forever begin
      seq_item_port.get_next_item(item);
      drive_item(item);
      seq_item_port.item_done();
    end
  endtask

  // ── Two-phase dispatch protocol ──
  //
  //  Phase 1: Assert proc_instr_valid with tag + op type.
  //           Hold until proc_instr_ready is sampled high.
  //
  //  Phase 2: Assert proc_data_valid with tag + addr + value.
  //           Hold until proc_data_ready is sampled high.
  //
  task drive_item(lsu_seq_item item);

    // ── Phase 1: Instruction ──
    vif.proc_instr_valid    <= 1'b1;
    vif.proc_instr_tag      <= item.tag;
    vif.proc_instr_is_write <= item.is_write;

    // Wait for handshake (valid & ready both high on a rising edge)
    do @(posedge vif.clk);
    while (!vif.proc_instr_ready);

    vif.proc_instr_valid <= 1'b0;

    `uvm_info("DRV", $sformatf("INSTR phase done: %s", item.convert2string()), UVM_HIGH)

    // ── Inter-phase gap ──
    repeat (item.inter_phase_delay) @(posedge vif.clk);

    // ── Phase 2: Data ──
    vif.proc_data_valid <= 1'b1;
    vif.proc_data_tag   <= item.tag;
    vif.proc_addr       <= item.addr;
    vif.proc_value      <= item.value;

    do @(posedge vif.clk);
    while (!vif.proc_data_ready);

    vif.proc_data_valid <= 1'b0;

    `uvm_info("DRV", $sformatf("DATA phase done:  %s", item.convert2string()), UVM_HIGH)
  endtask

endclass
