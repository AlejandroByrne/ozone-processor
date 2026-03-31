# Ozone Processor — 5-Day Tesla Interview Prep Plan

**Goal**: Back up every resume claim with working code and deep understanding.

**Resume claims to defend:**
1. Designed modular memory subsystem with custom LSQ and DRAM controller
2. Validated functional correctness through self-checking testbenches and FPGA synthesis
3. Defined inter-module interface protocols and timing constraints
4. Built UVM environment with constrained-random stimulus, scoreboard checking, and functional coverage

---

## Current State of the Codebase (Honest Assessment)

The memory subsystem (`mem/`) has **real bugs** across every major module.
This is actually an advantage — a DV engineer who builds a UVM testbench and
uses it to find and fix real bugs has the strongest possible interview story.

### Critical bugs already identified

| Module | Bug | Category |
|--------|-----|----------|
| `load_store_unit.sv` | Empty `always_ff` in `memory_interface` — dispatch fields never latched | Logic |
| `load_store_unit.sv` | Blocking assignments (`=`) in `always_ff` for `l1d_ready_out` | Syntax |
| `load_store_unit.sv` | `proc_data_ready_out` logic inverted (signals ready when busy) | Logic |
| `l1_data_cache.sv` | 64-bit virtual address truncated to 22-bit physical — no MMU | Arch |
| `l1_data_cache.sv` | MSHR write-forwarding incomplete (marked TODO) | Design Gap |
| `l1_data_cache.sv` | MSHR blocking never propagated to LSU as backpressure | Missing Signal |
| `cache.sv` | PLRU replacement is actually a mod-counter, not tree-PLRU | Algorithm |
| `cache.sv` | Flush clears tags without writing back dirty lines | Data Loss |
| `ddr4_dimm.sv` | `always_ff` missing `posedge`/`negedge` in sensitivity list | Syntax |
| `ddr4_dimm.sv` | DDR4 burst starts at index 1, skips first beat | Logic |
| `mem_scheduler.sv` | `incoming_req` used before initialization | Undefined |
| `mem_scheduler.sv` | Single `row_address` shared across all banks | Design Flaw |
| `bank_state.sv` | `ready` signal set to 1 during precharge (contradicts `blocked`) | Logic |
| `comb_util.sv` | `command_sender` has multiple clock edges in `always_ff` | Syntax |
| `comb_util.sv` | Burst timing condition is mathematically contradictory | Logic |
| `auto_refresh.sv` | Bit extraction syntax error in refresh counter comparison | Syntax |
| `mmu.sv` | Entirely unimplemented stub with syntax errors | Incomplete |

---

## Day 1 — Relearn the Design + Fix Showstoppers

**Morning (4h): Read and draw the architecture**

Go through each file and rebuild your mental model. Draw these on paper
(you will redraw them on a whiteboard at Tesla):

1. **Top-level block diagram**: LSU <-> L1D <-> LLC <-> DRAM controller <-> DIMM
2. **LSU internal pipeline**: instruction dispatch -> queue -> address resolution -> memory interface -> completion
3. **L1D state machine**: the 15-state FSM (IDLE -> CHECK_MSHR -> hit/miss paths -> MSHR drain)
4. **DRAM controller flow**: request queue -> bank state check -> command scheduling -> burst transfer

For each interface, write down:
- What signals cross the boundary (valid, ready, addr, data, tag, we)
- What the handshake protocol is (valid/ready, or valid/ack, or latency-insensitive)
- What happens on a stall (who holds, who retries)

**Afternoon (4h): Fix syntax-level showstoppers**

These prevent simulation and must be fixed first. They are mechanical fixes,
not design changes:

- [ ] `load_store_unit.sv`: Change blocking `=` to non-blocking `<=` in `always_ff` blocks
- [ ] `ddr4_dimm.sv`: Add `posedge`/`negedge` to `always_ff` sensitivity lists
- [ ] `comb_util.sv` `command_sender`: Fix multi-edge `always_ff` to `posedge clk_in or negedge rst_N_in`
- [ ] `auto_refresh.sv`: Fix bit extraction syntax (`{(REFRESH_INTERVAL-1)}[...]` is invalid)
- [ ] `mmu.sv`: Either remove the broken `cache#()` instantiation or stub it with pass-through wiring

Do NOT fix logic bugs yet. Those are what UVM will find.

**Evening (2h): Verify the existing Verilator testbenches compile and run**

```bash
make l1d       # L1D cache standalone
make lsu       # LSU standalone
make l1d_lsu   # LSU + L1D integration
make llc_dimm  # LLC + DIMM integration
```

Note which pass, which fail, and what the failure modes are.
This gives you baseline behavior before UVM.

---

## Day 2 — UVM Environment Scaffold

**Target DUT**: `load_store_unit` + `l1_data_cache` integrated (the LSU-L1D boundary).
This is the highest-value verification target because:
- It's the interface you defined between sub-teams (resume claim 3)
- It has the most bugs (Table above)
- It exercises both your LSQ and cache knowledge

**Morning (4h): UVM infrastructure**

Build these files under `mem/uvm/`:

```
mem/uvm/
  tb_top.sv              # Top-level module, instantiates DUT + interfaces
  lsu_l1d_pkg.sv         # Package importing UVM macros + all UVM classes
  lsu_l1d_if.sv          # SystemVerilog interface for proc<->LSU<->L1D signals
  lsu_l1d_env.sv         # uvm_env: instantiates agents, scoreboard, coverage
  lsu_l1d_test.sv        # Base test class (builds env, sets config)
```

**Interface definition** (`lsu_l1d_if.sv`) — two modports:
1. **Processor side** (stimulus drives this): `proc_instr_valid`, `proc_instr_tag`,
   `proc_instr_is_write`, `proc_data_valid`, `proc_data_tag`, `proc_addr`, `proc_value`
2. **Completion side** (monitor observes this): `completion_valid`, `completion_value`,
   `completion_tag`

**Afternoon (4h): Agent + Driver + Monitor**

```
mem/uvm/
  lsu_agent.sv           # uvm_agent: contains driver, monitor, sequencer
  lsu_driver.sv          # Drives proc-side interface per sequence items
  lsu_monitor.sv         # Observes both proc-side and completion-side
  lsu_seq_item.sv        # Transaction: {tag, op_type, addr, value, delay}
```

**Key driver protocol** (matches your 2-phase dispatch):
1. Assert `proc_instr_valid` with tag + op_type, wait for `proc_instr_ready`
2. Assert `proc_data_valid` with tag + addr + value, wait for `proc_data_ready`
3. For loads: wait for `completion_valid` with matching tag

**Evening (2h): Compile check**

Get the UVM environment to compile (even with empty scoreboard/coverage).
Use Questa, VCS, or Xcelium — NOT Verilator (Verilator has limited UVM support).

```bash
# Questa example
vlog -sv +incdir+mem/uvm mem/uvm/tb_top.sv
vsim -c tb_top -do "run 0; quit"
```

---

## Day 3 — Sequences + Scoreboard + First Bugs

**Morning (4h): Constrained-random sequences**

```
mem/uvm/
  lsu_base_seq.sv        # Base sequence (single load or store)
  lsu_back2back_seq.sv   # Back-to-back loads, back-to-back stores
  lsu_raw_seq.sv         # Store then load to same address (RAW hazard)
  lsu_stress_seq.sv      # Fill LSU queue to capacity (QUEUE_DEPTH=4)
  lsu_mixed_seq.sv       # Random interleaving of loads and stores
```

**Constraint examples for `lsu_seq_item`:**

```systemverilog
// Constrain addresses to trigger cache set conflicts
constraint addr_conflict_c {
  addr[5:0] == 6'b0;                    // Block-aligned
  addr[8:6] inside {[0:7]};             // Only 8 sets in L1D
  addr dist { [0:511] := 80, [512:4095] := 20 }; // Bias toward conflicts
}

// Constrain to exercise MSHR pressure
constraint mshr_pressure_c {
  op_type == LSU_OP_LOAD;
  addr[21:6] dist { [0:3] := 10, [4:255] := 90 }; // 4 MSHRs, force collisions
}
```

**Afternoon (4h): Reference model scoreboard**

```
mem/uvm/
  lsu_scoreboard.sv      # uvm_scoreboard with reference memory model
```

The scoreboard maintains a simple **associative array** (`logic [63:0] ref_mem[logic [63:0]]`)
that models expected memory state:

1. On store: `ref_mem[addr] = value`
2. On load completion: compare `completion_value` vs `ref_mem[addr]`
3. On timeout (no completion after N cycles): flag as error

This will immediately catch:
- The inverted `proc_data_ready_out` (stores accepted when they shouldn't be)
- The empty `memory_interface` `always_ff` (garbage data sent to L1D)
- Store-to-load forwarding failures

**Evening (2h): Run first regressions**

Run 100 random seeds. Expect failures. For each failure:
1. Record the seed
2. Note the failing check (data mismatch, timeout, protocol violation)
3. Map it to one of the known bugs in the table above

This is your **interview gold**: "My constrained-random testbench found N bugs in M seeds.
Here's one example — a store-followed-by-load to the same address returned stale data because
the LSU memory_interface had an empty always_ff block that never latched dispatch fields."

---

## Day 4 — Coverage + Fix Bugs Found by UVM

**Morning (4h): Functional coverage model**

```
mem/uvm/
  lsu_coverage.sv        # uvm_subscriber with covergroups
```

**Coverage points that matter for Tesla interviews:**

```systemverilog
covergroup lsu_protocol_cg @(posedge clk);
  // Operation type distribution
  cp_op_type: coverpoint op_type { bins load = {LSU_OP_LOAD}; bins store = {LSU_OP_STORE}; }

  // Queue occupancy when new request arrives
  cp_queue_depth: coverpoint queue_occupancy { bins empty = {0}; bins mid = {[1:2]}; bins full = {[3:4]}; }

  // Back-to-back same-address (RAW, WAW, WAR)
  cp_addr_hazard: coverpoint addr_hazard_type { bins raw = {RAW}; bins waw = {WAW}; bins war = {WAR}; }

  // MSHR behavior
  cp_mshr_state: coverpoint mshr_occupancy { bins none = {0}; bins partial = {[1:3]}; bins full = {4}; }
  cp_mshr_secondary: coverpoint secondary_miss;  // Load hits existing MSHR entry

  // Cache hit/miss
  cp_cache_outcome: coverpoint cache_hit { bins hit = {1}; bins miss = {0}; }

  // Cross coverage: operation type x cache outcome x queue depth
  cx_op_cache_queue: cross cp_op_type, cp_cache_outcome, cp_queue_depth;

  // Cross coverage: hazard type x MSHR state
  cx_hazard_mshr: cross cp_addr_hazard, cp_mshr_state;
endgroup
```

**Target**: 95%+ on protocol coverpoints, 80%+ on cross coverage.

**Afternoon (4h): Fix the bugs UVM found**

Now fix the logic bugs, in order of severity:

1. **`memory_interface` empty always_ff**: Latch `lat_addr`, `lat_is_store`, `lat_value`, `lat_tag`
   from inputs when dispatch state machine transitions from S_IDLE to S_DISPATCH
2. **`proc_data_ready_out` inversion**: Change to `!waiting_for_data`
3. **Cache PLRU**: Implement actual tree-PLRU (A-1 bits per set, tree traversal on access)
4. **DIMM burst off-by-one**: Start `burst_count` at 0, not 1
5. **Bank state ready/blocked contradiction**: `ready` should be 0 during precharge latency,
   set to 1 only when `cycle_count` reaches 0

For each fix, document:
- What the bug was
- How UVM exposed it (which sequence, what checker fired)
- What the fix was
- Why the original code was wrong

**Evening (2h): Re-run regressions, verify coverage improves**

Run 500 seeds. Coverage should jump significantly with bugs fixed.
Note any remaining holes — these become talking points about what you'd do next.

---

## Day 5 — FPGA Synthesis + Interview Practice

**Morning (3h): FPGA synthesis**

Your `.sdc` file targets a DE10-Nano (Cyclone V) at 50 MHz.

```bash
# Option A: Full Quartus flow (if you have Quartus installed)
quartus_map --read_settings_files=on --write_settings_files=off ozone -c ozone
quartus_fit ozone -c ozone
quartus_sta ozone -c ozone   # Static timing analysis
quartus_asm ozone -c ozone   # Generate .sof bitstream

# Option B: Synthesis-only (faster, still validates claim)
quartus_map --read_settings_files=on --write_settings_files=off ozone -c ozone
```

What to record from the reports:
- **Resource utilization**: ALMs, registers, memory bits, DSP blocks
- **Fmax**: Did it meet 50 MHz timing? If not, what's the critical path?
- **Warnings**: Inferred latches (these indicate bugs), multi-driven nets

Common synthesis issues to fix:
- Incomplete case/if statements → inferred latches
- `always_ff` blocks that don't assign on all paths
- Multi-driven nets from conflicting always blocks

**Afternoon (3h): Practice whiteboard explanations**

Practice these out loud, drawing diagrams. Time yourself — each should be
under 3 minutes:

1. **"Walk me through your memory subsystem architecture."**
   - Draw: LSU -> L1D (3-way, 8 sets, 4 MSHRs) -> LLC (16KB) -> DRAM Controller -> DDR4 DIMM
   - Mention: valid/ready handshakes, tag-based tracking, non-blocking cache

2. **"How does your load-store queue work?"**
   - 2-phase dispatch (instruction phase, data phase) — decouples decode from execute
   - Tag-based tracking through the memory hierarchy
   - Store-to-load forwarding by scanning older stores for address match
   - 4-entry queue with head/tail pointers

3. **"Explain your DRAM controller."**
   - Per-bank command queues (read, write, activate, precharge)
   - Bank state machine tracks active rows, enforces timing (tRCD, tCAS, tRP)
   - Auto-refresh module issues periodic refresh commands
   - Address mapping: row-bank_group-bank-column layout

4. **"Describe your UVM testbench."**
   - Draw the UVM topology: test -> env -> agent (driver + sequencer + monitor) -> scoreboard + coverage
   - TLM: monitor uses `uvm_analysis_port`, scoreboard and coverage are `uvm_subscriber`s
   - Constrained-random: address bias toward cache set conflicts and MSHR pressure
   - Coverage-driven: protocol covergroups with crosses on op_type x cache_outcome x queue_depth
   - Scoreboard: reference memory model (associative array), checks every load completion

5. **"Tell me about a bug your testbench found."**
   - Pick your best one. Structure: what the symptom was, how you root-caused it,
     what the fix was, why directed tests missed it.

**Evening (2h): Prepare for conceptual questions**

Tesla will also ask general DV concepts. Be ready for:

- **"What's the difference between assertions and functional coverage?"**
  Assertions check that something bad never happens (safety). Coverage checks that
  something good was exercised (liveness of verification). You need both.

- **"How do you know when verification is done?"**
  Coverage closure. Functional coverage hits targets, code coverage shows no
  unreachable dead code, and regression pass rate is 100% across N seeds.

- **"Explain constrained-random vs directed testing."**
  Directed finds known bugs. Constrained-random finds unknown bugs by exploring
  state space you didn't think of. The constraints keep stimulus legal while
  maximizing coverage.

- **"What is a TLM FIFO and why use it?"**
  Decouples producer (monitor) from consumer (scoreboard). Monitor writes
  via `analysis_port.write()`, scoreboard receives via `write()` method.
  One-to-many: single monitor can feed both scoreboard and coverage collector.

---

## File Checklist

By end of Day 5, these should exist and be working:

```
mem/uvm/
  tb_top.sv
  lsu_l1d_pkg.sv
  lsu_l1d_if.sv
  lsu_l1d_env.sv
  lsu_l1d_test.sv
  lsu_agent.sv
  lsu_driver.sv
  lsu_monitor.sv
  lsu_seq_item.sv
  lsu_base_seq.sv
  lsu_back2back_seq.sv
  lsu_raw_seq.sv
  lsu_stress_seq.sv
  lsu_mixed_seq.sv
  lsu_scoreboard.sv
  lsu_coverage.sv
```

Plus fixes in:
- `mem/src/load_store_unit.sv` (3 bugs)
- `mem/src/cache.sv` (PLRU, flush)
- `mem/src/ddr4_dimm.sv` (sensitivity list, burst)
- `mem/src/mem_control/bank_state.sv` (ready logic)
- `mem/src/mem_control/comb_util.sv` (command_sender)
- `mem/src/mem_control/auto_refresh.sv` (syntax)

---

## The Interview Narrative

When Tesla asks about this project, your story arc is:

> "I designed the memory subsystem for a 2-issue OOO ARM processor — specifically
> the load-store queue, L1D cache with MSHRs, and DDR4 controller with per-bank
> scheduling. I owned the interface protocols between the LSU and cache teams.
>
> After the RTL was integrated, I built a UVM testbench targeting the LSU-to-L1D
> interface with constrained-random stimulus. The key insight was biasing addresses
> toward cache set conflicts and MSHR saturation — this exposed bugs that directed
> tests completely missed, like [your best bug story].
>
> I closed coverage to 95% on protocol coverpoints and synthesized the full design
> on a Cyclone V at 50 MHz. The critical path was [whatever Quartus reports]."

This hits every bullet on your resume with specific, defensible details.
