# Last-Level Cache — Behavioral Specification

This document is the authoritative reference for the intended behavior of the
Ozone processor's Last-Level Cache (`last_level_cache`). It covers the LLC's
cache storage, DDR4 memory controller, request scheduling, and DRAM burst
protocol.

---

## 1  Overview

The LLC is the lowest and largest cache in the hierarchy. It sits between the
L1D cache above and a DDR4 SDRAM DIMM below. It is composed of three major
subsystems:

1. **Cache storage** — a parameterized generic `cache` module (the same module
   used inside L1D) that handles tag lookup, hit/miss detection, PLRU
   replacement, and eviction.
2. **Request scheduler** — decomposes physical addresses into DDR4 bank/row/col
   coordinates, queues commands per-bank, and schedules them respecting DDR4
   timing constraints.
3. **Command sender** — translates scheduled commands into DDR4 protocol
   signals on the memory bus and manages read/write burst sequencing.

The LLC is a **blocking** cache — it has no MSHRs. It processes one request at
a time through the cache FSM. While a miss is outstanding (waiting for DRAM),
the LLC cannot accept new requests from L1D.

| Property | Default Value |
|---|---|
| Associativity (A) | 3 (overridden to 2 or 8 in testbenches) |
| Block / line size (B) | 64 bytes (512 bits) |
| Capacity (C) | 16384 bytes (16 KB) |
| Word width (W) | 64 bits |
| Physical address width | 19 bits |
| Replacement policy | Pseudo-LRU (1 bit per way per set) |
| Write policy | Write-back, write-allocate |
| Inclusion policy | NINE (non-inclusive, non-exclusive) |
| CAS latency | 22 cycles |
| Row activation latency | 8 cycles |
| Precharge latency | 5 cycles |
| Row bits | 8 (256 rows per bank) |
| Column bits | 4 (16 columns per row) |
| Bank groups | 2 |
| Banks per group | 4 (8 banks total) |
| Bus width | 16 bits per chip (64-bit DQ bus) |

### 1.1  Derived Cache Geometry

With default parameters (A=3, B=64, C=16384, PADDR_BITS=19):

```
NUM_BLOCKS       = C / B                          = 256
NUM_SETS         = NUM_BLOCKS / A                  = 85 (truncated from 85.33)
BLOCK_OFFSET_BITS = log2(B)                        = 6
SET_INDEX_BITS    = ceil(log2(NUM_SETS))            = 7
TAG_BITS          = PADDR_BITS - SET_INDEX_BITS - BLOCK_OFFSET_BITS = 6
```

> **Note:** With A=3, the set count (256/3) is not an integer. Verilog integer
> division truncates to 85, leaving 1 block's worth of capacity unused. This
> is not a correctness issue but is worth noting. Testbenches typically use
> A=2 (128 sets) or A=8 (32 sets) which divide evenly.

---

## 2  Physical Address Geometry

### 2.1  Cache Address Decomposition

A 19-bit physical address is split for cache lookup:

```
[18 : 13]   [12 : 6]   [5 : 0]
   tag      set index  block offset
  6 bits     7 bits     6 bits
```

(Bit widths shown for default parameters; they adjust with A/C.)

### 2.2  DRAM Address Decomposition

The `address_parser` module maps the same 19-bit physical address to DDR4
coordinates. Bits `[2:0]` are a byte offset within a word and are ignored
by the scheduler:

```
[17 : 10]  [9]         [8 : 7]    [6 : 3]    [2 : 0]
   row     bank_group    bank      column    byte offset
  8 bits    1 bit       2 bits    4 bits      3 bits
```

Bit 18 is unused in this mapping (the address_parser only needs 18 bits of
the 19-bit address).

**Addressable space:** 2^8 rows × 2^1 bank groups × 2^2 banks × 2^4 columns ×
8 bytes = 256 KB of DRAM.

---

## 3  Interfaces

### 3.1  Higher-Level Cache Interface (L1D above)

| Signal | Dir | Width | Description |
|---|---|---|---|
| `hc_valid_in` | in | 1 | L1D has a valid request (miss fetch or eviction writeback) |
| `hc_ready_out` | out | 1 | LLC is ready to accept a request |
| `hc_addr_in` | in | 19 | Physical address of the request |
| `hc_value_in` | in | 64 | Write data (single word, for word-granularity writes) |
| `hc_we_in` | in | 1 | 0 = read (L1D miss), 1 = write (L1D eviction) |
| `hc_line_in` | in | 512 | Full cache line data (for eviction writebacks from L1D) |
| `hc_cl_in` | in | 1 | Cache-line write enable (1 = `hc_line_in` is a full line) |
| `hc_valid_out` | out | 1 | LLC is returning valid data to L1D |
| `hc_ready_in` | in | 1 | L1D is ready to accept LLC's response |
| `hc_addr_out` | out | 19 | Address of the returned data |
| `hc_value_out` | out | 64 | Returned data (single 64-bit word) |

**Request handshake:**
A request is accepted when `hc_valid_in && hc_ready_out` on a rising edge.
The LLC latches `hc_addr_in`, `hc_value_in`, `hc_we_in`, `hc_line_in`, and
`hc_cl_in`.

**Response handshake:**
A response is delivered when `hc_valid_out` is high. Acknowledged when
`hc_ready_in` is sampled high.

### 3.2  Memory Bus Interface (DRAM below)

| Signal | Dir | Width | Description |
|---|---|---|---|
| `mem_bus_addr_out` | out | 19 | Encoded DDR4 command + address (see §6.3) |
| `mem_bus_value_io` | inout | 64 | Bidirectional data bus (DQ lines) |
| `mem_bus_valid_out` | out | 1 | LLC has a valid command for DRAM |
| `mem_bus_ready_out` | out | 1 | LLC is ready to receive from DRAM (always high) |
| `mem_bus_ready_in` | in | 1 | DRAM controller ready (largely unused — synchronization via fixed latencies) |
| `mem_bus_valid_in` | in | 1 | DRAM data is valid |

**Bus protocol:** The memory bus does **not** use ready/valid handshaking for
data transfer. Synchronization is achieved through fixed, known latencies
(CAS latency, activation latency, precharge latency). The `mem_bus_value_io`
bus is tri-stated by the command sender except during write bursts.

### 3.3  Control Signals

| Signal | Dir | Width | Description |
|---|---|---|---|
| `clk_in` | in | 1 | System clock |
| `rst_N_in` | in | 1 | Active-low synchronous reset |
| `cs_in` | in | 1 | Chip select / enable |
| `flush_in` | in | 1 | Flush all cache state (invalidate all, does not writeback) |

---

## 4  Cache Storage Subsystem

The LLC instantiates the same generic `cache` module used by L1D. All
behavioral details in this section match the L1D cache spec's description
of the generic cache, with LLC-specific parameterization.

### 4.1  Tag Array

Each way × set stores:

```
struct tag_entry {
    valid : 1 bit
    dirty : 1 bit
    tag   : TAG_BITS (6 bits with default params)
};
```

### 4.2  Data Array

```
cache_data[way][set] : 512-bit cache line
```

Word access: `cache_data[way][set][offset*8 +: 64]` extracts a 64-bit word.

### 4.3  PLRU Replacement

Identical to L1D's PLRU (see L1D spec §4.3). Per-set bit vector, one bit per
way. On access, set the accessed way's bit; if all bits become 1, clear the
others. On replacement, select the first way with bit=0.

### 4.4  Cache FSM States

| State | Description |
|---|---|
| **IDLE** | Waiting for request from L1D or fill data from DRAM |
| **LOOKUP** | Tag comparison across all ways in the target set |
| **RESPOND_HC** | Send hit data (64-bit word) back to L1D |
| **WRITE_CACHE** | Install data (from DRAM fill or L1D write) into cache |
| **SEND_LOWER_CACHE_REQ** | Send miss address to memory controller |
| **EVICT_BLOCK** | Send dirty victim line to memory controller for writeback |
| **FLUSH_CACHE_STATE** | Invalidate all entries |

---

## 5  Operations (Cache Level)

### 5.1  Read Hit (L1D Miss, LLC Hit)

L1D sends a read request (`hc_we_in=0`) for a block that exists in LLC.

1. **IDLE → LOOKUP:** Tag comparison finds a match.
2. **LOOKUP → RESPOND_HC:** Cache reads the 64-bit word at the block offset.
3. **RESPOND_HC → IDLE:** LLC asserts `hc_valid_out=1` with the word on
   `hc_value_out`. Waits for `hc_ready_in` to complete handshake.

PLRU updated for the hit way.

### 5.2  Write Hit (L1D Eviction, LLC Hit)

L1D evicts a dirty line that already exists in the LLC (same tag).

1. **IDLE → LOOKUP:** Tag match found.
2. **LOOKUP → WRITE_CACHE:** If `hc_cl_in=1`, the full 512-bit line from
   `hc_line_in` overwrites the existing line. If `hc_cl_in=0`, a single
   64-bit word from `hc_value_in` is written at the offset.
3. **WRITE_CACHE → IDLE:** Tag updated: valid=1, dirty=1, tag preserved.

### 5.3  Read Miss (L1D Miss, LLC Miss)

L1D requests a block that is not in the LLC.

1. **IDLE → LOOKUP:** No tag match. PLRU selects a victim way.
2. **Victim check:**
   - If victim is **valid and dirty** → **EVICT_BLOCK** first (see §5.5).
   - If victim is **clean or invalid** → **SEND_LOWER_CACHE_REQ** directly.
3. **SEND_LOWER_CACHE_REQ:** LLC outputs the miss address to the request
   scheduler (`lc_valid_out=1`, `we_out=0`). Waits for `lc_ready_in` (the
   scheduler accepted the request). Returns to **IDLE**.
4. **Later — DRAM response:** When the command sender has received the full
   burst from DRAM, it asserts `sdram_valid_in=1` with the 512-bit line on
   `sdram_value_in`. The cache module sees this as `lc_valid_in`.
5. **IDLE → LOOKUP → WRITE_CACHE:** The fill line is installed in the victim
   way. Tag set to: valid=1, dirty=0 (fills from DRAM are always clean).
6. After installation, the cache's HC-side response must deliver the requested
   word back to L1D (see §9 for current issues with this path).

### 5.4  Write Miss (L1D Eviction, LLC Miss)

L1D evicts a dirty line whose block address is not in the LLC.

1. **LOOKUP:** No tag match. Victim selected.
2. If victim dirty → **EVICT_BLOCK** (writeback to DRAM), then **WRITE_CACHE**.
3. If victim clean/invalid → **WRITE_CACHE** directly.
4. The evicted L1D line is installed into the LLC. With `hc_cl_in=1` the full
   512-bit line from `hc_line_in` is written. Tag: valid=1, dirty=1.

### 5.5  Eviction to DRAM

When a dirty victim must be replaced:

1. **EVICT_BLOCK:** The victim's 512-bit line data is placed on
   `lc_value_out`. `lc_valid_out=1`, `we_out=1`. The evicted block's address
   (reconstructed from victim tag + set index + zero offset) is on
   `lc_addr_out`.
2. The request scheduler accepts the write and queues it for the appropriate
   DRAM bank.
3. When `lc_ready_in` (scheduler acceptance) is sampled high, the cache
   transitions to **WRITE_CACHE** to install the new data.

### 5.6  Flush

`flush_in` while in IDLE triggers **FLUSH_CACHE_STATE**:
- All tag entries have `valid` and `dirty` cleared across all ways and sets.
- PLRU bits cleared to 0.
- Returns to IDLE in one cycle.
- **No dirty writeback occurs.** Data in dirty lines is lost.

### 5.7  Reset

Active-low synchronous reset:
- All registers cleared.
- Tag array invalidated.
- Cache FSM set to IDLE.
- Memory controller registers reset.
- Bank state: all banks idle, ready to precharge.

---

## 6  Memory Controller Subsystem

### 6.1  Request Scheduler (`request_scheduler`)

The scheduler receives miss/eviction requests from the cache module and
translates them into DDR4 bank commands, respecting timing constraints.

#### 6.1.1  Address Parsing

The `address_parser` module decomposes the physical address:

```
Input:  19-bit physical address
Output: row[7:0], col[3:0], bank_group[0:0], bank[1:0]

Mapping:
  addr[2:0]  → byte offset (ignored)
  addr[6:3]  → column (4 bits)
  addr[8:7]  → bank (2 bits)
  addr[9:9]  → bank group (1 bit)
  addr[17:10]→ row (8 bits)
```

#### 6.1.2  Per-Bank Command Queues

For each of the 8 banks, there are **4 dual-queues** (ready + pending stages):

| Queue | Purpose | Latency for promotion |
|---|---|---|
| **Read** | Pending read commands | 1 cycle |
| **Write** | Pending write commands | 1 cycle |
| **Activation** | Row-open commands | ACTIVATION_LATENCY (8 cycles) |
| **Precharge** | Row-close commands | PRECHARGE_LATENCY (5 cycles) |

Each dual-queue (`mem_cmd_queue`) has:
- A **ready queue**: newly enqueued requests, immediately schedulable.
- A **pending queue**: requests that have waited their required latency,
  eligible for promotion to the next stage.

**Promotion logic:** A pending entry is promoted when
`pending_top.cycle_count + LATENCY <= current_cycle_count`. This ensures
timing constraints are respected.

**Queue pipeline for a miss to an inactive bank:**
```
Incoming → Precharge Queue → [wait PRECHARGE_LATENCY] →
           Activation Queue → [wait ACTIVATION_LATENCY] →
           Read/Write Queue → [schedule onto bus]
```

**Queue pipeline for a hit to an active bank with correct row:**
```
Incoming → Read/Write Queue → [schedule onto bus]
```

#### 6.1.3  Request Routing

When a new request arrives (`valid_in`), the scheduler checks bank state:

1. **Bank is ready (precharged, not active):**
   Route to that bank's **activation queue**. The bank needs a row-open before
   the read/write can proceed.

2. **Bank is active, and the active row matches the request's row:**
   Route directly to the bank's **read queue** or **write queue** depending on
   `write_in`. This is a **row buffer hit** — fastest path.

3. **Bank is active, but a different row is open (row conflict):**
   Route to the bank's **precharge queue**. Must close the current row before
   opening the new one.

#### 6.1.4  Command Scheduling Priority

Each cycle, when the command sender is ready (`cmd_ready` and not `bursting`),
the scheduler selects one command to issue. Priority order:

1. **Auto-refresh** (highest) — if the refresh module has a pending refresh
   command, it preempts all other scheduling. Refresh issues a precharge to
   the target bank.

2. **Read** (if read starvation detected) — if any bank has a ready read
   request that is older than the corresponding write request, and at least
   4 cycles have elapsed since the last read command. Prevents write
   starvation of reads.

3. **Write** — if not bursting and at least 4 cycles since last write. The
   4-cycle gap accounts for burst timing on the shared data bus.

4. **Activate** — if no read/write is ready, issue an activation for a bank
   that has a pending activation and is not blocked.

5. **Precharge** (lowest) — close a row to prepare for a future activation.

Within each priority level, banks are scanned from index 0 upward; the first
bank with a ready command wins.

### 6.2  Bank State Tracker (`sdram_bank_state`)

Tracks the state of each of the 8 banks independently:

| State | Meaning |
|---|---|
| Ready (`ready=1, active=0`) | Bank is precharged, idle. Must activate before access. |
| Active (`active=1, blocked=0`) | Row buffer open, ready for read/write. |
| Blocked (`blocked=1`) | Bank is in a timing window (activation or precharge in progress). Cannot receive commands. |

**Transitions:**

```
           activate                          precharge
Ready ──────────────► Blocked(ACT) ─[8 cyc]─► Active
                                                │
                                           precharge
                                                │
                                                ▼
                                      Blocked(PRE) ─[5 cyc]─► Ready
```

- **Activate:** Sets `active=1`, `blocked=1`, starts countdown from
  `ACTIVATION_LATENCY`. When countdown reaches 0, `blocked` clears.
- **Precharge:** Sets `active=0`, `ready=1`, `blocked=1`, starts countdown
  from `PRECHARGE_LATENCY`. When countdown reaches 0, `blocked` clears.

The scheduler only sends commands to non-blocked banks.

### 6.3  Command Sender (`command_sender`)

Translates scheduled commands into DDR4 protocol wire encoding and handles
data burst sequencing.

#### 6.3.1  DDR4 Address Encoding

The `mem_bus_addr_out` bus encodes DDR4 protocol signals:

```
Bit [18]: CS_N   (chip select, active low)
Bit [17]: ACT_N  (activate command indicator)
Bits [16:14]: {RAS_N, CAS_N, WE_N}  (command encoding)
Bits [13:12]: Bank group + bank
Bits [11:0]:  Row or column address (context-dependent)
```

| Command | CS_N | ACT_N | RAS_N | CAS_N | WE_N |
|---|---|---|---|---|---|
| Activate | 0 | 0 | x | x | x |
| Read | 0 | 1 | 1 | 0 | 1 |
| Write | 0 | 1 | 1 | 0 | 0 |
| Precharge | 0 | 1 | 0 | 1 | 0 |

#### 6.3.2  Read Burst Sequence

After a READ command is sent to DRAM:

1. **CAS_LATENCY** (22) cycles later: first word of data appears on
   `mem_bus_value_io`.
2. **8 consecutive cycles:** 8 × 64-bit words are captured, reconstructing
   the full 512-bit cache line.
3. Words are captured at column offsets `(col_start + i) & 0x7` for
   `i = 0..7`, supporting wrap-around burst addressing.
4. After all 8 words captured, `act_out` (mapped to `sdram_valid_in`)
   is asserted, signaling the cache module that the fill data is ready.
5. The assembled 512-bit line is placed on `val_out` → `sdram_value_in`.

During read bursts, the `bursting` signal is asserted to prevent the
scheduler from issuing commands that would conflict with incoming data.

#### 6.3.3  Write Burst Sequence

When a WRITE command is scheduled:

1. The command sender drives `mem_bus_value_io` with the first word of the
   cache line.
2. Over 8 consecutive cycles, all 8 words are driven onto the bus
   (`val_in[burst_counter]`).
3. `mem_bus_value_io` is normally tri-stated (`64'bz`) and only driven
   during write bursts.
4. `bursting` is asserted during write bursts to block new command
   scheduling.

#### 6.3.4  Command Sender Internal Queue

The command sender maintains a 32-entry read request queue to track
outstanding reads and their expected completion times. Entries are:
- Enqueued when a READ command is issued.
- Dequeued at `cycle_counter = enqueue_time + CAS_LATENCY + 3`, when the
  burst is expected to have completed.

### 6.4  Auto-Refresh (`auto_refresh`)

DDR4 requires periodic refresh to maintain data integrity.

- **Refresh interval:** 64,000,000 cycles (configurable).
- When triggered, the module iterates through all banks × rows, issuing
  precharge commands.
- Refresh takes priority over normal scheduling.
- The refresh sequence cycles through banks and rows over multiple cycles,
  with each step taking up to 16 cycles (`refresh_stage` 0–F).

---

## 7  End-to-End Request Flow

### 7.1  L1D Read Miss → LLC Hit

```
L1D                        LLC Cache               DRAM
 │                            │                      │
 ├──hc_valid_in=1, we=0──────►│                      │
 │                    IDLE→LOOKUP                     │
 │                    tag match (hit)                 │
 │                    LOOKUP→RESPOND_HC               │
 │◄──hc_valid_out=1──────────┤                       │
 │    hc_value_out = word     │                      │
 │──hc_ready_in=1────────────►│                      │
 │                    RESPOND_HC→IDLE                  │
```

### 7.2  L1D Read Miss → LLC Miss (Clean Victim)

```
L1D                   LLC Cache             Scheduler          DRAM
 │                       │                     │                │
 ├──hc_valid_in=1, we=0─►│                     │                │
 │               IDLE→LOOKUP                    │                │
 │               no match, victim clean         │                │
 │               LOOKUP→SEND_LOWER_CACHE_REQ    │                │
 │                       ├──lc_valid=1, we=0───►│                │
 │                       │               route to bank queue     │
 │                       │◄──lc_ready=1─────────┤                │
 │                       │  SEND_LC_REQ→IDLE    │                │
 │                       │                      ├──activate──────►│
 │                       │                      │   [8 cyc]      │
 │                       │                      ├──read──────────►│
 │                       │                      │   [22 cyc CAS] │
 │                       │                      │◄──8 word burst─┤
 │                       │◄──sdram_valid=1──────┤                │
 │                       │   sdram_value=line   │                │
 │               IDLE→LOOKUP→WRITE_CACHE         │                │
 │               install line (valid=1,dirty=0)  │                │
 │               [response to L1D — see §9]      │                │
```

### 7.3  L1D Eviction → LLC (Writeback)

```
L1D                   LLC Cache             Scheduler          DRAM
 │                       │                     │                │
 ├──hc_valid_in=1, we=1─►│                     │                │
 │   hc_line_in = line   │                     │                │
 │   hc_cl_in = 1        │                     │                │
 │               IDLE→LOOKUP                    │                │
 │               [hit → WRITE_CACHE]            │                │
 │               [miss, dirty victim:]          │                │
 │               LOOKUP→EVICT_BLOCK             │                │
 │                       ├──lc_valid=1, we=1───►│                │
 │                       │   lc_value=victim    │                │
 │                       │◄──lc_ready=1─────────┤                │
 │               EVICT_BLOCK→WRITE_CACHE         │                │
 │               install L1D line               │                │
 │               WRITE_CACHE→IDLE                │                │
 │                       │                      ├──write burst──►│
```

---

## 8  Timing and Latency

### 8.1  LLC Cache Hit Latency

From request acceptance to response: determined by the cache FSM pipeline
depth (IDLE → LOOKUP → RESPOND_HC, with registered outputs ≈ 3-4 cycles).

### 8.2  LLC Cache Miss Latency (DRAM)

Worst-case path for a miss to a bank with a row conflict:

| Phase | Cycles |
|---|---|
| Cache LOOKUP + route to scheduler | ~2 |
| Precharge (close current row) | 5 |
| Activate (open new row) | 8 |
| CAS latency | 22 |
| Burst transfer (8 words) | 8 |
| Cache install + response | ~3 |
| **Total** | **~48 cycles** |

Best-case (row buffer hit, bank not blocked):

| Phase | Cycles |
|---|---|
| Cache LOOKUP + route to scheduler | ~2 |
| Read command issued immediately | 0 |
| CAS latency | 22 |
| Burst transfer | 8 |
| Cache install + response | ~3 |
| **Total** | **~35 cycles** |

### 8.3  Burst Timing Constraints

- **Minimum 4 cycles between consecutive reads** (enforced by
  `last_read + 4 <= cycle_counter` check).
- **Minimum 4 cycles between consecutive writes** (enforced by
  `last_write + 4 <= cycle_counter` check).
- **No commands during active burst** (`bursting` signal blocks scheduler).

---

## 9  Known RTL Issues and Design Gaps

### 9.1  LLC Returns Words, Not Cache Lines (Critical)

The generic `cache` module's `hc_value_out` is only **64 bits** wide (W=64).
The L1D expects **512-bit cache line** fills on `lc_value_in`. There is no
path in the current LLC to return a full cache line to the L1D after a miss.

**Evidence:** In `l1d_llc_tb.sv`, `lc_value_in` is connected to `temp_512`
(all zeros) rather than to the LLC's output, with a TODO comment.

**Impact:** LLC miss responses cannot deliver actual data to L1D in the
integrated configuration. The L1D UVM testbench sidesteps this by using the
behavioral `llc_responder` class which directly drives 512-bit lines.

**Intended fix:** The LLC needs either:
- A separate 512-bit line output port for miss responses to L1D, or
- An 8-cycle burst protocol between LLC and L1D (complex), or
- The `cache` module parameterized with W=512 when used in the LLC (simplest
  but changes the HC interface width).

### 9.2  L1D Eviction Line Not Properly Received

In `l1d_llc_tb.sv`, `hc_cl_in` is tied to 0 (with a TODO comment). This means
the cache module never sees a full cache-line write from L1D — it would only
write a single 64-bit word from `hc_value_in`, which is also tied to zero.

**Impact:** L1D evictions to LLC lose 7 of 8 words in the cache line.

**Intended fix:** The L1D must drive `hc_cl_in=1` and provide the full line on
`hc_line_in` for eviction writebacks. The LLC's wrapper already has these ports
(`hc_line_in`, `hc_cl_in`); they just need to be properly connected.

### 9.3  Non-Integer Set Count with A=3

`NUM_SETS = 16384 / 64 / 3 = 85.33`. Integer truncation gives 85 sets,
wasting 1 block of capacity. Not a functional bug but may cause synthesis
warnings. Consider using A=2 or A=4 for the LLC, or adjusting C to be
divisible by A×B.

### 9.4  Blocking Cache Limits Throughput

The LLC has no MSHRs. While servicing a DRAM miss (~35-48 cycles), it cannot
accept new requests from L1D. If L1D has two outstanding misses (both MSHRs
used), the second miss will stall until the first completes.

**Impact:** Effective miss latency doubles for back-to-back misses. Acceptable
for initial bring-up but limits performance.

### 9.5  `command_sender` Mixed Assignment Styles

The `command_sender` module uses both blocking (`=`) and non-blocking (`<=`)
assignments within the same `always_ff` block. It also has a sensitivity list
that includes `negedge clk_in` (dual-edge clocking). This is non-standard and
may cause simulation/synthesis mismatches.

**Specific instances:**
- `read_bursting = 1'b1;` (blocking) on line 276 inside an `always_ff` block
  that otherwise uses `<=`.
- `val_out[burst_col_index] = mem_bus_value_io;` (blocking) in the burst
  capture logic.
- Sensitivity on both `posedge clk_in` and `negedge clk_in` in the burst
  counter block.

### 9.6  Read Burst Dequeue Timing

The command sender dequeues a read request from its internal queue at
`CAS_LATENCY + 3` cycles after enqueue, but `act_out` (which signals data
ready to the cache) is also asserted at `CAS_LATENCY + 3`. However, the
burst itself runs from `CAS_LATENCY` to `CAS_LATENCY + 7`. This means
the data-ready signal fires **before the burst completes** (at cycle +3 of
8), which could deliver a partially filled cache line.

### 9.7  Scheduler `process_bank_commands` Uses `ref` on Combinational Signals

The function passes queue parameter arrays by reference and modifies them
inside the function body. While this works in simulation, it creates complex
combinational feedback paths that may not synthesize cleanly.

### 9.8  `mem_bus_ready_in` Unused

The LLC comment notes that `mem_bus_ready_in` "might go unused" because DRAM
synchronization is latency-based, not handshake-based. The signal is declared
but not meaningfully consumed. This is fine architecturally but the port
should be documented as reserved/unused.

---

## 10  LLC's Role in L1D Verification

For L1D-focused UVM verification, the LLC is **replaced by the behavioral
`llc_responder`** class. This is the correct approach because:

1. The real LLC has unresolved interface issues (§9.1, §9.2) that would
   prevent clean integration.
2. L1D verification needs a controlled, deterministic memory model — not a
   multi-cycle DDR4 pipeline.
3. The `llc_responder` provides:
   - Configurable response latency (default 5 cycles).
   - Deterministic data generation (each word = its own byte address).
   - Immediate eviction acceptance.
   - 512-bit cache line responses (matching L1D's `lc_value_in` width).

### 10.1  LLC Responder Behavior (Golden Model for L1D Tests)

**Backing store:** Associative array `mem[block_addr] → 512-bit line`.

**Data generation:** For any block address not yet in the backing store,
a cache line is generated where each 64-bit word contains:
```
word[i] = block_base_address + (i * 8)
```
Where `block_base_address = {addr[21:6], 6'b0}` (block-aligned byte address).

**On read miss from L1D** (`lc_valid_out && !lc_we_out`):
1. Wait `response_latency` cycles.
2. Look up (or auto-generate) the cache line.
3. Drive `lc_valid_in=1`, `lc_addr_in=req_addr`, `lc_value_in=line`.
4. Hold until `lc_ready_out` is asserted by L1D.

**On eviction writeback from L1D** (`lc_valid_out && lc_we_out`):
1. Accept immediately (no latency).
2. Store the line in the backing store: `mem[addr[21:6]] = data`.
3. Subsequent reads to that block return the written-back data.

**On concurrent miss responses:** The responder forks a new task for each
miss request, so multiple outstanding misses are handled independently with
their own latency delays.

---

## 11  Future: LLC-Level Verification

When the LLC itself becomes the DUT, its golden model will need to track:

| Aspect | Model requirement |
|---|---|
| Cache hit/miss | Tag array + PLRU, same as L1D model |
| DRAM request generation | Verify correct address parsing and bank routing |
| Bank state machine | Track activate/precharge/blocked per bank |
| Scheduling correctness | Verify timing constraints (CAS, tRCD, tRP) |
| Burst data integrity | Verify all 8 words of a burst are captured correctly |
| Eviction writeback | Verify dirty lines reach DRAM with correct data |
| Auto-refresh | Verify refresh commands at correct intervals |

This will require a cycle-accurate model of both the cache FSM and the DDR4
timing state machine, significantly more complex than the L1D golden model.
