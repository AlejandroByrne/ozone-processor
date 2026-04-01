// Processor-facing interface (stimulus boundary)
interface lsu_proc_if (input logic clk, input logic rst_n);

  // Instruction phase
  logic             proc_instr_valid;
  logic [9:0]       proc_instr_tag;
  logic             proc_instr_is_write;
  logic             proc_instr_ready;

  // Data phase
  logic             proc_data_valid;
  logic [9:0]       proc_data_tag;
  logic [63:0]      proc_addr;
  logic [63:0]      proc_value;
  logic             proc_data_ready;

  // Completion
  logic             completion_valid;
  logic [63:0]      completion_value;
  logic [9:0]       completion_tag;

endinterface : lsu_proc_if


// Lower-cache-facing interface (LLC responder boundary)
interface llc_if (input logic clk, input logic rst_n);

  // From L1D (miss requests / evictions)
  logic             lc_valid_out;
  logic             lc_ready_out;
  logic [21:0]      lc_addr_out;
  logic [511:0]     lc_value_out;
  logic             lc_we_out;

  // To L1D (responses)
  logic             lc_valid_in;
  logic             lc_ready_in;
  logic [21:0]      lc_addr_in;
  logic [511:0]     lc_value_in;

endinterface : llc_if
