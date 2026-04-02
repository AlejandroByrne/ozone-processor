`timescale 1ns/1ps

class l1d_driver extends uvm_driver #(l1d_item);
  `uvm_component_utils(l1d_driver)

  virtual l1d_lsu_if vif;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual l1d_lsu_if)::get(this, "", "l1d_lsu_vif", vif)) begin
      `uvm_fatal("DRV", "Could not get l1d_lsu_vif")
    end
  endfunction

  task run_phase(uvm_phase phase);
    // Initialize
    vif.lsu_valid_in <= 1'b0;
    vif.lsu_we_in    <= 1'b0;
    vif.lsu_addr_in  <= '0;
    vif.lsu_value_in <= '0;
    vif.lsu_tag_in   <= '0;
    vif.lsu_ready_in <= 1'b1; // LSU is always ready to receive completions

    forever begin
      seq_item_port.get_next_item(req);
      drive_item(req);
      seq_item_port.item_done();
    end
  endtask 

  task drive_item(l1d_item item);
    // Drive request
    vif.lsu_valid_in <= 1'b1;
    vif.lsu_tag_in   <= item.tag;
    vif.lsu_we_in    <= item.is_write;
    vif.lsu_addr_in  <= item.addr;
    vif.lsu_value_in <= item.is_write ? item.value : 64'd0;

    // Wait until L1D accepts the request
    do @(posedge vif.clk);
    while (vif.lsu_ready_out !== 1'b1);

    vif.lsu_valid_in <= 1'b0;

    `uvm_info("DRV", $sformatf("Driven: %s", item.convert2string()), UVM_HIGH)
  endtask
endclass
