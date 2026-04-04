# Ozone OOO CPU - Module Topology

## Mermaid Diagram

Paste the code block below into https://mermaid.live or any Mermaid renderer.

```mermaid
graph TB
    classDef frontend fill:#2563eb,stroke:#1e40af,color:#fff
    classDef backend fill:#7c3aed,stroke:#5b21b6,color:#fff
    classDef mem fill:#059669,stroke:#047857,color:#fff
    classDef exec fill:#d97706,stroke:#b45309,color:#fff
    classDef reg fill:#dc2626,stroke:#b91c1c,color:#fff
    classDef util fill:#6b7280,stroke:#4b5563,color:#fff
    classDef dram fill:#0d9488,stroke:#0f766e,color:#fff

    subgraph TOP["ozone (top-level)"]
        direction TB

        subgraph FE["frontend"]
            direction TB
            BP["branch_pred"]
            L0["l0_instruction_cache"]
            L1I["l1_instr_cache"]
            FETCH["fetch"]
            DECODE["decode"]
            RAS["stack (RAS)"]
            ALIGN1["align_instructions (L0)"]
            ALIGN2["align_instructions (L1I)"]
            CACHE_I["cache (generic)"]

            BP --> L0
            BP --> RAS
            L1I --> CACHE_I
            FETCH --> ALIGN1
            FETCH --> ALIGN2
            BP -->|"pred_pc, branch_data"| FETCH
            L0 -->|"l0_cacheline"| FETCH
            L1I -->|"l1i_cacheline"| FETCH
            FETCH -->|"fetched_instrs"| DECODE
        end

        IQ["instruction_queue"]

        subgraph BE["backend"]
            direction TB

            subgraph RENAME["Register Renaming"]
                direction LR
                RAT["rat"]
                RRAT["rrat"]
                FRL["frl"]
            end

            ROB["reorder_buffer"]
            ROB_Q["reorder_buffer_queue"]
            ROB --> ROB_Q

            subgraph EXEC["Execution Units"]
                direction LR
                ALU["alu_ins_decoder"]
                FPU_DEC["fpu_ins_decoder"]
                LSU_DEC["lsu_ins_decoder"]
                BRU["bru_ins_decoder"]
            end

            subgraph FPU_UNITS["FPU Pipeline"]
                direction LR
                FPADD["fpadder"]
                FPMUL["fpmult_rtl"]
            end

            REGFILE["reg_file"]

            RAT -->|"rob_entry"| ROB
            FRL -->|"phys_regs"| RAT
            RRAT -->|"freed_regs"| FRL
            ROB -->|"retire"| RRAT
            ROB -->|"dispatch"| ALU
            ROB -->|"dispatch"| FPU_DEC
            ROB -->|"dispatch"| LSU_DEC
            ROB -->|"dispatch"| BRU
            FPU_DEC --> FPADD
            FPU_DEC --> FPMUL
            ALU -->|"writeback"| ROB
            FPU_DEC -->|"writeback"| ROB
            LSU_DEC -->|"writeback"| ROB
            BRU -->|"writeback"| ROB
            REGFILE ---|"read/write"| EXEC
            RAT -->|"intermediate writes"| REGFILE
        end

        subgraph MEMSYS["Memory Subsystem"]
            direction TB

            LSU["load_store_unit"]
            LSU_CTRL["lsu_control"]
            LSU_Q["lsu_queue"]
            MEM_IF["memory_interface"]

            subgraph L1D_MOD["l1_data_cache"]
                direction TB
                L1D_FSM["L1D State Machine"]
                MSHR0["mshr_queue #0"]
                MSHR1["mshr_queue #1"]
                CACHE_D["cache (generic)"]
                L1D_FSM --> MSHR0
                L1D_FSM --> MSHR1
                L1D_FSM --> CACHE_D
            end

            subgraph LLC_MOD["last_level_cache"]
                direction TB
                LLC_CACHE["cache (generic)"]
                subgraph MEMCTRL["Memory Controller"]
                    direction TB
                    SCHED["request_scheduler"]
                    CMD_Q["mem_cmd_queue"]
                    REQ_Q["mem_req_queue"]
                    BANK_ST["sdram_bank_state"]
                    CMD_SEND["command_sender"]
                    ADDR_PARSE["address_parser"]
                    AUTO_REF["auto_refresh"]
                    PMUX["priority_mux"]
                    SCHED --> CMD_Q
                    SCHED --> REQ_Q
                    SCHED --> BANK_ST
                    SCHED --> CMD_SEND
                    SCHED --> ADDR_PARSE
                    SCHED --> AUTO_REF
                    SCHED --> PMUX
                end
                LLC_CACHE --> SCHED
            end

            subgraph DIMM["ddr4_dimm"]
                direction LR
                CHIP0["ddr4_sdram_chip #0"]
                CHIP1["ddr4_sdram_chip #1"]
                CHIP2["ddr4_sdram_chip #2"]
                CHIP3["ddr4_sdram_chip #3"]
            end

            LSU --> LSU_CTRL
            LSU_CTRL --> LSU_Q
            LSU_CTRL --> MEM_IF
            MEM_IF -->|"valid/ready + addr/data"| L1D_MOD
            L1D_MOD -->|"miss request"| LLC_MOD
            LLC_MOD -->|"fill line (512b)"| L1D_MOD
            LLC_MOD -->|"ACT/RD/WR/PRE cmds"| DIMM
            DIMM -->|"data burst"| LLC_MOD
        end

        %% Top-level connections
        DECODE -->|"decoded uops"| IQ
        IQ -->|"instruction packets"| RAT
        LSU_DEC -->|"addr, tag, we"| LSU
        LSU -->|"completion data"| LSU_DEC
        BRU -->|"mispred, target_pc"| BP
        L1I -->|"lc_valid/addr"| LLC_MOD
        LLC_MOD -->|"fill cacheline"| L1I
    end

    class BP,L0,L1I,FETCH,DECODE,RAS,ALIGN1,ALIGN2,CACHE_I frontend
    class RAT,RRAT,FRL,REGFILE reg
    class ROB,ROB_Q backend
    class ALU,FPU_DEC,LSU_DEC,BRU,FPADD,FPMUL exec
    class LSU,LSU_CTRL,LSU_Q,MEM_IF,L1D_FSM,MSHR0,MSHR1,CACHE_D,LLC_CACHE,SCHED,CMD_Q,REQ_Q,BANK_ST,CMD_SEND,ADDR_PARSE,AUTO_REF,PMUX mem
    class CHIP0,CHIP1,CHIP2,CHIP3 dram
    class IQ util
```

## Module Summary Table

| Subsystem | Module | File | Key Role |
|-----------|--------|------|----------|
| **Top** | `ozone` | `src/ozone.sv` | Top-level: instantiates frontend, IQ, backend, LSU, L1D |
| **Frontend** | `frontend` | `src/frontend/frontend.sv` | Wraps fetch pipeline |
| | `branch_pred` | `src/frontend/branch_pred.sv` | GHR+PHT predictor, owns L0 and RAS |
| | `l0_instruction_cache` | `src/frontend/cache/l0_instruction_cache.sv` | L0 I-cache (private to BP) |
| | `l1_instr_cache` | `src/frontend/cache/l1_instr_cache.sv` | L1 I-cache, wraps generic `cache` |
| | `fetch` | `src/frontend/fetch.sv` | Aligns cachelines into instruction bundles |
| | `decode` | `src/frontend/decode.sv` | Cracks instructions into micro-ops |
| | `align_instructions` | `src/frontend/fetch.sv` | Extracts instructions from cacheline by offset |
| | `stack` (RAS) | `src/util/stack.sv` | Return Address Stack for call/ret prediction |
| **IQ** | `instruction_queue` | `src/util/instr-queue.sv` | FIFO bridging frontend decode to backend RAT |
| **Backend** | `backend` | `src/backend/backend.sv` | Wraps rename, ROB, exec units, regfile |
| | `rat` | `src/backend/registers/rat.sv` | Register Allocation Table (arch -> phys mapping) |
| | `rrat` | `src/backend/registers/rrat.sv` | Retirement RAT (committed mappings) |
| | `frl` | `src/backend/registers/frl.sv` | Free Register List (circular queue) |
| | `reg_file` | `src/backend/registers/reg_file.sv` | Physical register file (16R/8W ports) |
| | `reorder_buffer` | `src/backend/insn_ds/reorder_buffer.sv` | ROB: tracks in-flight insns, dispatches, retires |
| | `reorder_buffer_queue` | `src/backend/insn_ds/reorder_buffer.sv` | Circular queue backing the ROB |
| | `alu_ins_decoder` | `src/backend/exec/alu_ins_decoder.sv` | ALU: combinational execute + writeback |
| | `fpu_ins_decoder` | `src/backend/exec/fpu_ins_decoder.sv` | FPU decoder: coordinates adder + multiplier |
| | `fpadder` | `src/fpu/fpadder.sv` | IEEE 754 FP add/sub (multi-cycle) |
| | `fpmult_rtl` | `src/fpu/fpmult.sv` | IEEE 754 FP multiply (multi-cycle, shift-add) |
| | `lsu_ins_decoder` | `src/backend/exec/lsu_ins_decoder.sv` | LSU decoder: bridges ROB dispatch to memory |
| | `bru_ins_decoder` | `src/backend/exec/bru_ins_decoder.sv` | Branch unit: resolves branches, feeds back |
| **Memory** | `load_store_unit` | `mem/src/load_store_unit.sv` | LSU: queues + interfaces with L1D |
| | `lsu_control` | `mem/src/load_store_unit.sv` | LSU orchestration |
| | `lsu_queue` | `mem/src/load_store_unit.sv` | Pending LD/ST queue |
| | `memory_interface` | `mem/src/load_store_unit.sv` | L1D protocol interface |
| | `l1_data_cache` | `mem/src/l1_data_cache.sv` | L1D: 3-way SA, 1536B, non-blocking, 2 MSHRs |
| | `mshr_queue` | `mem/src/l1_data_cache.sv` | MSHR entry queue (16 entries each) |
| | `cache` (generic) | `mem/src/cache.sv` | Reusable cache storage (used by L1I, L1D, LLC) |
| | `last_level_cache` | `mem/src/last_level_cache.sv` | LLC: 8-way SA, 16KB, embeds DRAM controller |
| | `request_scheduler` | `mem/src/mem_control/mem_scheduler.sv` | DRAM request scheduling (row-buffer aware) |
| | `command_sender` | `mem/src/mem_control/comb_util.sv` | Formats DDR4 commands |
| | `address_parser` | `mem/src/mem_control/comb_util.sv` | Physical addr -> row/bank/col |
| | `sdram_bank_state` | `mem/src/mem_control/bank_state.sv` | Per-bank FSM tracking |
| | `auto_refresh` | `mem/src/mem_control/auto_refresh.sv` | JEDEC refresh scheduling |
| | `mem_cmd_queue` | `mem/src/mem_control/req_queue.sv` | Command queue to DRAM |
| | `mem_req_queue` | `mem/src/mem_control/req_queue.sv` | Request tracking queue |
| | `priority_mux` | `mem/src/priority_mux.sv` | Priority arbitration |
| **DRAM** | `ddr4_dimm` | `mem/src/ddr4_dimm.sv` | DIMM model (4 chips) |
| | `ddr4_sdram_chip` | `mem/src/ddr4_dimm.sv` | Individual DRAM chip with bank FSM |

## Architecture Quick Facts

- **4-wide superscalar** (up to 4 instructions decoded/dispatched per cycle)
- **4 functional units**: ALU (1-cycle), FPU (multi-cycle), BRU (1-cycle), LSU (variable)
- **Out-of-order execution** via ROB with dispatch-on-ready scheduling
- **Register renaming**: RAT + RRAT + FRL cycle (allocate on decode, free on retire)
- **Physical register file**: ~64 regs, 16 read ports (4 FUs x 4 operands), 8 write ports
- **2-level I-cache**: L0 (private to branch predictor) + L1I (generic cache)
- **Branch prediction**: GHR + PHT pattern history table, Return Address Stack
- **3-level data memory**: L1D (3-way, 1536B, 2 MSHRs) -> LLC (8-way, 16KB) -> DDR4
- **DDR4 DRAM**: Modeled with real timing (CAS=22, tRCD=8, tRP=5), 4-chip DIMM, auto-refresh
- **Non-blocking L1D**: MSHRs enable secondary miss coalescing and store-to-load forwarding
- **Write-back policy**: Dirty lines evicted on replacement, not written through
- **NINE inclusion**: Non-inclusive non-exclusive between L1D and LLC
