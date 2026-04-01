`timescale 1ns/1ps

module test_dpi;

  // 1. Import the C++ functions so SystemVerilog can see them
  import "DPI-C" function void mem_write(longint unsigned addr, longint unsigned data);
  import "DPI-C" function longint unsigned mem_read(longint unsigned addr);
  import "DPI-C" function void mem_reset();

  initial begin
    $display("\n--- Starting Golden Model Manual Probe ---");

    // 2. Reset the model
    mem_reset();
    $display("[%0t] Model Reset.", $time);

    // 3. Test a Read before any Write (Checking default behavior)
    // The model is programmed to return the address itself if empty.
    $display("[%0t] Reading addr 0x100... Expected: 0x100, Got: 0x%0h", $time, mem_read(64'h100));

    // 4. Test a Write
    $display("[%0t] Writing 0xDEADBEEF to addr 0x200...", $time);
    mem_write(64'h200, 64'hDEADBEEF);

    // 5. Read it back
    $display("[%0t] Reading addr 0x200... Expected: 0xDEADBEEF, Got: 0x%0h", $time, mem_read(64'h200));

    // 6. Test Alignment logic
    // The C++ model aligns to 8 bytes. Let's see if 0x203 returns the same data as 0x200.
    $display("[%0t] Reading addr 0x203 (unaligned)... Expected: 0xDEADBEEF, Got: 0x%0h", $time, mem_read(64'h203));

    $display("--- Probe Finished ---\n");
    $finish;
  end

endmodule
