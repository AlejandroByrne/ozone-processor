`timescale 1ns/1ps

class l1d_monitor extends uvm_monitor;
  `uvm_component_utils(l1d_monitor)

  virtual l1d_lsu_if vif;

  uvm_analysis_port #(l1d_item) req_ap;
  uvm_analysis_port #(l1d_item) comp_ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
    req_ap = new("req_ap", this);
    comp_ap = new("comp_ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual l1d_lsu_if)::get(this, "", "l1d_lsu_vif", vif)) begin
      `uvm_fatal("MON", "Could not get l1d_lsu_vif")
    end
  endfunction

  task run_phase(uvm_phase phase);
    fork
      monitor_requests();
      monitor_completions();
    join
  endtask

  task monitor_requests();
    forever begin
      @(posedge vif.clk);
      // if (vif.lsu_valid_in === 1'b1) begin
      //   `uvm_info("MON", $sformatf("Observed lsu_valid_in=1, lsu_ready_out=%b", vif.lsu_ready_out), UVM_HIGH)
      // end
      if (vif.lsu_valid_in === 1'b1 && vif.lsu_ready_out === 1'b1) begin
        l1d_item item = l1d_item::type_id::create("req_item");
        item.is_write = vif.lsu_we_in;
        item.tag      = vif.lsu_tag_in;
        item.addr     = vif.lsu_addr_in;
        item.value    = vif.lsu_value_in;
        
        `uvm_info("MON", $sformatf("REQ: %s", item.convert2string()), UVM_HIGH)
        req_ap.write(item);
      end
    end
  endtask

  task monitor_completions();
    forever begin
      @(posedge vif.clk);
      if (vif.lsu_valid_out === 1'b1 && vif.lsu_ready_in === 1'b1) begin
        l1d_item item = l1d_item::type_id::create("comp_item");
        item.tag              = vif.lsu_tag_out;
        item.completion_received = 1;
        item.completion_value = vif.lsu_write_complete_out ? 64'd0 : vif.lsu_value_out;

        `uvm_info("MON", $sformatf("COMP: tag=%0d val=0x%0h write_comp=%b", 
                  item.tag, item.completion_value, vif.lsu_write_complete_out), UVM_HIGH)
        comp_ap.write(item);
      end
    end
  endtask
endclass
