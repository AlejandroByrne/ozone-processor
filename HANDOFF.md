# Ozone Processor — UVM Testbench Handoff

## Strict Direction

Back up the resume claim: "Built UVM environment with constrained-random stimulus, scoreboard checking, and functional coverage" targeting the **memory subsystem only** (LSU + L1D cache). No yak-shaving. Don't touch the CPU pipeline, frontend, backend, DRAM controller, or DDR4 DIMM. Those are interview talking points from code review, not UVM targets.

---

## What Exists

14 UVM files in `uvm/`, ~1470 lines, targeting `load_store_unit` + `l1_data_cache` as the DUT:

| File | Role |
|------|------|
| `tb_top.sv` | Top-level: clock, reset, DUT instantiation (LSU wired to L1D), interface registration |
| `lsu_l1d_pkg.sv` | Package: imports UVM, includes all classes in dependency order |
| `lsu_l1d_if.sv` | Two interfaces: `lsu_proc_if` (proc-side stimulus), `llc_if` (LLC responder boundary) |
| `lsu_seq_item.sv` | Transaction: is_write, tag, addr, value, inter_phase_delay. Constraints bias toward set conflicts |
| `lsu_driver.sv` | Implements 2-phase dispatch protocol (instr phase then data phase, matched by tag) |
| `lsu_monitor.sv` | Two analysis ports (req_ap, comp_ap). Correlates instr+data phases by tag |
| `lsu_agent.sv` | Standard active agent: driver + sequencer + monitor |
| `llc_responder.sv` | Backing memory model. Default: each 64-bit word = its own address. Responds to L1D misses after configurable latency |
| `lsu_scoreboard.sv` | Self-checking. ref_mem tracks expected state. Stores update model, load completions checked against model. Timeout detection for stuck loads |
| `lsu_coverage.sv` | 3 covergroups: op_type x cache_set, hazard classification (RAW/WAW/WAR/RAR), address patterns (same-addr, set-conflict, adjacent) |
| `lsu_l1d_env.sv` | Env: agent + llc_responder + scoreboard + coverage. TLM wired |
| `lsu_sequences.sv` | 7 sequences: base, load-only, store-only, RAW hazard, WAW hazard, set-conflict/eviction, stress (queue fill), mixed random |
| `lsu_l1d_test.sv` | 8 test classes with drain time, one per sequence |
| `Makefile` | Questa/VCS/Xcelium support. Targets: compile, run, run_waves, regress (all 8 tests) |

**RTL lints clean** under Verilator. Port wiring manually verified against RTL module declarations.

**Cannot compile UVM on this machine** — only Verilator available, no Questa/VCS/Xcelium.

---

## Known Bugs in DUT (What UVM Should Find)

These are in the modules under test. UVM sequences are designed to hit them.

### load_store_unit.sv

| Bug | Lines | What Happens | Which Sequence Hits It |
|-----|-------|-------------|----------------------|
| Empty `always_ff` in `memory_interface` | 767-769 | Dispatch fields (addr, value, tag, we) never latched. L1D gets garbage | Any — lsu_load_test will show mismatch immediately |
| Blocking `=` in `always_ff` for `l1d_ready_out` | ~780 | Race condition, ready may glitch | lsu_stress_seq (back-to-back pressure) |
| Store-to-store forwarding writes zero | queue forwarding logic | WAW: second store's value lost, forwarded as 0 | lsu_waw_hazard_seq |

### l1_data_cache.sv

| Bug | What Happens | Which Sequence Hits It |
|-----|-------------|----------------------|
| MSHR write-forwarding incomplete (TODO) | Store miss followed by load to same addr may return stale data | lsu_raw_hazard_seq |
| MSHR blocking not propagated as backpressure | LSU keeps sending when all 4 MSHRs full, requests silently dropped | lsu_stress_seq, lsu_set_conflict_seq |

### cache.sv (instantiated inside l1_data_cache)

| Bug | What Happens | Which Sequence Hits It |
|-----|-------------|----------------------|
| PLRU is mod-counter, not tree-PLRU | Eviction pattern is predictable round-robin, not LRU. Functional but suboptimal | lsu_set_conflict_seq (5 tags in 3-way set) |
| Flush doesn't writeback dirty lines | Data loss on flush. Not hit by UVM since flush_in tied to 0, but worth mentioning in interview |

---

## Known Bugs Outside DUT (Interview Talking Points Only)

These are in modules NOT tested by UVM. Mention them as "bugs I found during code review":

- **ozone.sv**: `proc_instr` and `proc_data` driven by same signal; `is_write` hardcoded to 0
- **rat.sv**: No intra-group forwarding (two renames in same cycle to same dest, second doesn't see first)
- **lsu_ins_decoder.sv**: No `UOP_STORE` case; writeback uses wrong ptr field
- **reorder_buffer.sv**: Stores never transition READY->DONE
- **ddr4_dimm.sv**: Missing posedge, burst off-by-one
- **mem_scheduler.sv**: Undefined `incoming_req`, single `row_address` shared across banks
- **bank_state.sv**: `ready=1` during precharge contradicts `blocked`
- **comb_util.sv**: Multiple clock edges in `always_ff`, contradictory burst condition
- **auto_refresh.sv**: Bit extraction syntax error
- **mmu.sv**: Unimplemented stub with syntax errors

---

## Immediate Next Steps

1. **Get access to Questa, VCS, or Xcelium**. This Mac only has Verilator (no UVM support).

2. **Compile**:
   ```bash
   cd ozone-processor/uvm
   make SIM=questa compile    # or SIM=vcs, SIM=xcelium
   ```
   Fix any compile errors (expect minor type/scope issues, not structural problems).

3. **Smoke test** — start simple:
   ```bash
   make SIM=questa TEST=lsu_load_test run
   ```
   Load-only, no forwarding needed. If the scoreboard reports mismatches here, it's the `memory_interface` empty `always_ff` bug.

4. **Full regression**:
   ```bash
   make SIM=questa regress
   ```
   Runs all 8 tests. Document every failure: seed, failing check, root cause bug.

5. **Fix bugs found by UVM**, re-run, document the fix. Each fixed bug = one interview story.

6. **Check coverage**:
   ```bash
   make SIM=questa TEST=lsu_random_test VERBOSITY=UVM_LOW run
   ```
   Coverage report prints in `report_phase`. Target: all op_cg bins hit, all hazard types exercised.

---

## What NOT To Do

- Don't touch the frontend, backend, or pipeline integration
- Don't build UVM for the DRAM controller or DDR4 DIMM
- Don't try to fix ozone.sv's top-level wiring bugs (they're in the CPU integration, not the memory subsystem)
- Don't add SystemVerilog assertions to the RTL (nice-to-have, not on the critical path)
- Don't try to get Verilator working with UVM
- Don't synthesize until UVM regression passes
