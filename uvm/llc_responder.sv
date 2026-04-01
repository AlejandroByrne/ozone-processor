// Simple LLC memory model.
//
// Responds to L1D cache miss requests with cacheline data from a backing
// store. Accepts eviction writebacks. Configurable response latency.
//
// The backing store is initialized so that each 64-bit word contains its
// own byte address — this makes load results deterministic and easy to
// check in the scoreboard.

class llc_responder extends uvm_component;
  `uvm_component_utils(llc_responder)

  virtual llc_if vif;

  // Backing memory: indexed by block address (addr >> 6 for 64-byte blocks)
  logic [511:0] mem [logic [15:0]];   // 16-bit block address → 512-bit cacheline

  // Configurable miss response latency (in clock cycles)
  int unsigned response_latency = 5;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db#(virtual llc_if)::get(this, "", "llc_vif", vif))
      `uvm_fatal("NOVIF", "Could not get llc_vif from config_db")
  endfunction

  // Generate a cacheline from an address.
  // Each 64-bit word = block_base_address + word_offset_in_bytes.
  // E.g., block at byte address 0x100:
  //   word[0] = 0x100, word[1] = 0x108, ..., word[7] = 0x138
  function logic [511:0] generate_cacheline(logic [21:0] block_addr);
    logic [511:0] line;
    logic [63:0] base = {42'b0, block_addr[21:6], 6'b0};  // zero out block offset
    for (int w = 0; w < 8; w++) begin
      line[w*64 +: 64] = base + (w * 8);
    end
    return line;
  endfunction

  // Look up (or auto-generate) a cacheline
  function logic [511:0] read_line(logic [21:0] addr);
    logic [15:0] blk = addr[21:6];
    if (!mem.exists(blk))
      mem[blk] = generate_cacheline(addr);
    return mem[blk];
  endfunction

  // Accept an eviction writeback
  function void write_line(logic [21:0] addr, logic [511:0] data);
    logic [15:0] blk = addr[21:6];
    mem[blk] = data;
    `uvm_info("LLC", $sformatf("Writeback: blk=0x%0h", blk), UVM_HIGH)
  endfunction

  task run_phase(uvm_phase phase);
    // Drive defaults
    vif.lc_valid_in <= 1'b0;
    vif.lc_ready_in <= 1'b1;    // always ready to accept requests
    vif.lc_addr_in  <= '0;
    vif.lc_value_in <= '0;

    @(posedge vif.rst_n);
    @(posedge vif.clk);

    forever begin
      @(posedge vif.clk);

      // Check for L1D request (valid & ready handshake)
      if (vif.lc_valid_out && vif.lc_ready_in) begin
        logic [21:0] req_addr = vif.lc_addr_out;
        logic        is_write = vif.lc_we_out;
        logic [511:0] wr_data = vif.lc_value_out;

        if (is_write) begin
          // Eviction writeback — accept immediately
          write_line(req_addr, wr_data);
        end else begin
          // Read miss — respond after latency
          fork
            respond_to_miss(req_addr);
          join_none
        end
      end
    end
  endtask

  task respond_to_miss(logic [21:0] addr);
    logic [511:0] line = read_line(addr);

    `uvm_info("LLC", $sformatf("Miss request: addr=0x%0h, responding in %0d cycles",
              addr, response_latency), UVM_HIGH)

    repeat (response_latency) @(posedge vif.clk);

    // Drive response, hold until L1D accepts (ready handshake)
    vif.lc_valid_in <= 1'b1;
    vif.lc_addr_in  <= addr;
    vif.lc_value_in <= line;

    do @(posedge vif.clk);
    while (!vif.lc_ready_out);

    vif.lc_valid_in <= 1'b0;

    `uvm_info("LLC", $sformatf("Miss response accepted: addr=0x%0h", addr), UVM_MEDIUM)
  endtask

endclass
