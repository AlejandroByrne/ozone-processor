`timescale 1ns/1ps

module l1d_smoke_tb;

  parameter int A = 3;
  parameter int B = 64;
  parameter int C = 1536;
  parameter int PADDR_BITS = 22;
  parameter int MSHR_COUNT = 4;
  parameter int TAG_BITS = 10;

  logic clk;
  logic rst_n;
  logic cs_n;
  logic flush;

  // LSU Interface
  logic lsu_valid_in;
  logic lsu_ready_in;
  logic [63:0] lsu_addr_in;
  logic [63:0] lsu_value_in;
  logic [TAG_BITS-1:0] lsu_tag_in;
  logic lsu_we_in;

  logic lsu_valid_out;
  logic lsu_ready_out;
  logic [63:0] lsu_addr_out;
  logic [63:0] lsu_value_out;
  logic lsu_write_complete_out;
  logic [TAG_BITS-1:0] lsu_tag_out;

  // LLC Interface
  logic lc_ready_in;
  logic lc_valid_in;
  logic [PADDR_BITS-1:0] lc_addr_in;
  logic [8*B-1:0] lc_value_in;

  logic lc_valid_out;
  logic lc_ready_out;
  logic [PADDR_BITS-1:0] lc_addr_out;
  logic [8*B-1:0] lc_value_out;
  logic lc_we_out;

  l1_data_cache #(
    .A(A), .B(B), .C(C), .PADDR_BITS(PADDR_BITS), .MSHR_COUNT(MSHR_COUNT), .TAG_BITS(TAG_BITS)
  ) dut (
    .clk_in(clk),
    .rst_N_in(rst_n),
    .cs_N_in(cs_n),
    .flush_in(flush),
    .lsu_valid_in(lsu_valid_in),
    .lsu_ready_in(lsu_ready_in),
    .lsu_addr_in(lsu_addr_in),
    .lsu_value_in(lsu_value_in),
    .lsu_tag_in(lsu_tag_in),
    .lsu_we_in(lsu_we_in),
    .lsu_valid_out(lsu_valid_out),
    .lsu_ready_out(lsu_ready_out),
    .lsu_addr_out(lsu_addr_out),
    .lsu_value_out(lsu_value_out),
    .lsu_write_complete_out(lsu_write_complete_out),
    .lsu_tag_out(lsu_tag_out),
    .lc_ready_in(lc_ready_in),
    .lc_valid_in(lc_valid_in),
    .lc_addr_in(lc_addr_in),
    .lc_value_in(lc_value_in),
    .lc_valid_out(lc_valid_out),
    .lc_ready_out(lc_ready_out),
    .lc_addr_out(lc_addr_out),
    .lc_value_out(lc_value_out),
    .lc_we_out(lc_we_out)
  );

  initial begin
    clk = 0;
    forever #5 clk = ~clk;
  end

  initial begin
    rst_n = 0;
    cs_n = 1;
    flush = 0;
    lsu_valid_in = 0;
    lsu_ready_in = 1;
    lsu_addr_in = 0;
    lsu_value_in = 0;
    lsu_tag_in = 0;
    lsu_we_in = 0;
    lc_ready_in = 1;
    lc_valid_in = 0;
    lc_addr_in = 0;
    lc_value_in = 0;

    #50;
    rst_n = 1;
    cs_n = 0;
    #20;

    // --- Smoke Test: Simple Store ---
    $display("[%0t] Starting Simple Store...", $time);
    @(posedge clk);
    lsu_valid_in <= 1;
    lsu_addr_in <= 64'h1000;
    lsu_value_in <= 64'hDEADBEEFCAFEBABE;
    lsu_we_in <= 1;
    lsu_tag_in <= 10'h1;

    wait (lsu_ready_out);
    @(posedge clk);
    lsu_valid_in <= 0;
    lsu_we_in <= 0;

    // Wait for write complete
    fork
      begin
        wait (lsu_write_complete_out);
        $display("[%0t] Store Completed!", $time);
      end
      begin
        #1000;
        if (!lsu_write_complete_out) $display("[%0t] ERROR: Store Timed Out!", $time);
      end
    join_any
    disable fork;

    #50;

    // --- Smoke Test: Simple Load ---
    $display("[%0t] Starting Simple Load...", $time);
    @(posedge clk);
    lsu_valid_in <= 1;
    lsu_addr_in <= 64'h1000;
    lsu_we_in <= 0;
    lsu_tag_in <= 10'h2;

    wait (lsu_ready_out);
    @(posedge clk);
    lsu_valid_in <= 0;

    // Wait for response
    fork
      begin
        wait (lsu_valid_out);
        $display("[%0t] Load Completed! Value = %h", $time, lsu_value_out);
      end
      begin
        #1000;
        if (!lsu_valid_out) $display("[%0t] ERROR: Load Timed Out!", $time);
      end
    join_any
    disable fork;

    #100;
    $finish;
  end

endmodule
