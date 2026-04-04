# L1 Data Cache — Behavioral Specification

This document is the authoritative reference for the intended behavior of the
Ozone processor's L1 data cache (`l1_data_cache`). A cycle-accurate C++ golden
model and every UVM scoreboard check must agree with this spec.

---

## 1  Overview

The L1D cache is a **non-blocking, write-back, PIPT** (Physically Indexed
Physically Tagged) cache that sits between the Load-Store Unit (LSU) and the
Last-Level Cache (LLC). It accepts one request at a time from the LSU, services
hits in a small fixed number of cycles, and uses Miss Status Holding Registers
(MSHRs) to track outstanding misses so that subsequent requests can still be
accepted while earlier misses are in flight.

| Property | Value |
|---|---|
| Associativity (A) | 3-way |
| Block / line size (B) | 64 bytes (512 bits) |
| Capacity (C) | 1536 bytes |
| Number of sets | 8 (C / B / A) |
| Replacement policy | Pseudo-LRU (1 bit per way per set) |
| Write policy | Write-back, write-allocate |
| Inclusion policy | NINE (non-inclusive, non-exclusive) |
| MSHR count | 2 |
| MSHR queue depth | 16 entries per MSHR |
| Physical address width | 22 bits |
| Data word width | 64 bits (8 bytes) |
| Processor tag width | 10 bits |

---

## 2  Address Geometry

A 22-bit physical address is decomposed as:

```
[21 : 9]   [8 : 6]   [5 : 0]
  tag      set index  block offset
 13 bits    3 bits     6 bits
```

- **Block offset** (6 bits) — byte position within a 64-byte line.
  Word-aligned accesses use bits `[5:3]` to select one of eight 64-bit words.
  Bits `[2:0]` must be zero for 8-byte-aligned accesses.
- **Set index** (3 bits) — selects one of 8 sets.
- **Tag** (13 bits) — compared against stored tags for hit detection.

The **block address** is bits `[21:6]` (address with offset stripped). This is
the unit of comparison inside MSHRs — two requests target the same cache line
iff their block addresses match.

---

## 3  Interfaces

### 3.1  LSU Interface (upstream / requester side)

All signals are synchronous to `clk_in`, active-high unless noted.

| Signal | Dir | Width | Description |
|---|---|---|---|
| `lsu_valid_in` | in | 1 | LSU is presenting a valid request |
| `lsu_ready_out` | out | 1 | L1D can accept a new request this cycle |
| `lsu_addr_in` | in | 64 | Request address (physical addr in lower 22 bits) |
| `lsu_value_in` | in | 64 | Store data (ignored for loads) |
| `lsu_tag_in` | in | 10 | Processor-assigned request tag — travels with the request and is returned with the completion |
| `lsu_we_in` | in | 1 | 0 = load, 1 = store |
| `lsu_valid_out` | out | 1 | L1D is presenting a valid completion |
| `lsu_ready_in` | in | 1 | LSU is ready to accept a completion |
| `lsu_addr_out` | out | 64 | Completion address (zero-extended from 22-bit physical) |
| `lsu_value_out` | out | 64 | Load data (undefined for store completions) |
| `lsu_tag_out` | out | 10 | Tag of the completing request |
| `lsu_write_complete_out` | out | 1 | High for exactly one cycle when a store completes |

**Request handshake:**
A request is accepted on a rising clock edge where `lsu_valid_in && lsu_ready_out` are both high. On that edge the L1D latches `lsu_addr_in`, `lsu_value_in`, `lsu_tag_in`, and `lsu_we_in`. Until the L1D returns to IDLE, these latched values are frozen.

**Completion handshake:**
A completion is delivered on a rising clock edge where `lsu_valid_out` is high.
For loads, `lsu_value_out` carries the data and `lsu_tag_out` identifies the
request. For stores, `lsu_write_complete_out` is asserted for one cycle and
`lsu_tag_out` identifies the store. `lsu_value_out` is undefined on store
completions.

> **Completion ordering:** Completions are *not* guaranteed to be in program
> order. A load that hits may complete before an earlier load that missed.
> The `lsu_tag_out` field is the sole mechanism for the LSU to match
> completions to issued requests.

### 3.2  LLC Interface (downstream / memory side)

| Signal | Dir | Width | Description |
|---|---|---|---|
| `lc_valid_out` | out | 1 | L1D is presenting a request to the LLC |
| `lc_ready_in` | in | 1 | LLC can accept the request |
| `lc_addr_out` | out | 22 | Physical block address of miss or eviction |
| `lc_value_out` | out | 512 | Evicted cache line data (valid only for writebacks) |
| `lc_we_out` | out | 1 | 0 = read request (miss fetch), 1 = write request (eviction/writeback) |
| `lc_valid_in` | in | 1 | LLC is returning data |
| `lc_ready_out` | out | 1 | L1D is ready to accept LLC data |
| `lc_addr_in` | in | 22 | Address of the returning line |
| `lc_value_in` | in | 512 | Returning cache line data |

**Miss request:** L1D asserts `lc_valid_out` with `lc_we_out=0` and the block
address. The request is accepted when `lc_ready_in` is sampled high on the
same edge.

**Eviction / writeback:** L1D asserts `lc_valid_out` with `lc_we_out=1`, the
evicted block address on `lc_addr_out`, and the dirty line data on
`lc_value_out`. Accepted when `lc_ready_in` is high. No data is expected back
from the LLC for a writeback.

**Fill response:** LLC asserts `lc_valid_in` with the block address and 512-bit
data. L1D acknowledges by asserting `lc_ready_out`. Fill responses are
**prioritized** over new LSU requests (see §6).

### 3.3  Control Signals

| Signal | Dir | Width | Description |
|---|---|---|---|
| `clk_in` | in | 1 | Clock |
| `rst_N_in` | in | 1 | Active-low synchronous reset |
| `cs_N_in` | in | 1 | Active-low chip select (enable) |
| `flush_in` | in | 1 | Flush all lines (invalidate, clear PLRU, reset MSHRs) |

---

## 4  Internal Structures

### 4.1  Tag Array

Each of the 3 ways × 8 sets stores a tag entry:

```
struct tag_entry {
    valid : 1 bit
    dirty : 1 bit
    tag   : 13 bits
};
```

- `valid` — set when a line is installed; cleared on flush or reset.
- `dirty` — set when a store writes to the line; cleared when the line is
  installed from LLC (fills are always clean). A dirty line must be written
  back to the LLC before its way can be reused.

### 4.2  Data Array

```
cache_data[way][set] : 512-bit cache line
```

Reads and writes address a 64-bit word within a line using the block offset
bits `[5:3]`. Full-line writes are used when installing data from the LLC.

### 4.3  PLRU State

Each set has a 3-bit vector `plru_bits[set][0:2]`, one bit per way.

**On access (hit or install to way W):**
1. Set `plru_bits[set][W] = 1`.
2. If all three bits are now 1, clear the other two bits to 0.

**On replacement (selecting a victim):**
Select the first way whose bit is 0, scanning from way 0 upward:
- If `plru_bits[set][0] == 0` → evict way 0
- Else if `plru_bits[set][1] == 0` → evict way 1
- Else → evict way 2

### 4.4  MSHR Entries and Queues

There are `MSHR_COUNT` (2) independent MSHRs. Each MSHR is a FIFO queue of up
to 16 entries:

```
struct mshr_entry {
    paddr          : 22 bits   // full physical address of the request
    no_offset_addr : 16 bits   // block address [21:6], used for CAM matching
    we             : 1 bit     // 0 = load, 1 = store
    data           : 64 bits   // store data (meaningful only when we=1)
    tag            : 10 bits   // processor tag for LSU completion routing
    valid          : 1 bit     // entry is in use
};
```

The **front of the queue** (`req_out`) represents the oldest pending request
for that MSHR. The `no_offset_addr` of the front entry identifies which cache
line the entire MSHR is tracking.

An MSHR is **free** when its front-of-queue entry has `valid == 0` (equivalently,
the queue is empty).

---

## 5  Operations

### 5.1  Load Hit

**Precondition:** LSU presents a load (`lsu_we_in=0`), the address maps to a
set where one of the 3 ways has `valid=1` and `tag` matches.

**Sequence:**
1. **IDLE → READ_CACHE:** L1D latches inputs, issues a read to the internal
   cache module.
2. **READ_CACHE → WAIT_CACHE:** Cache performs tag lookup.
3. **WAIT_CACHE → SEND_RESP_HC:** Cache reports a hit with the 64-bit word.
4. **SEND_RESP_HC → IDLE:** L1D asserts `lsu_valid_out=1` with the load data
   on `lsu_value_out`, the request's physical address (zero-extended to 64 bits)
   on `lsu_addr_out`, and the processor tag on `lsu_tag_out`.

**PLRU update:** The accessed way's bit is set during the cache LOOKUP state.

**Latency:** Fixed, determined by the cache-module pipeline depth (IDLE →
cache IDLE → LOOKUP → RESPOND_HC → registered output ≈ several cycles).

### 5.2  Store Hit

**Precondition:** LSU presents a store (`lsu_we_in=1`), tag match exists.

**Sequence:**
1. **IDLE → WRITE_CACHE:** L1D latches inputs, issues a write to the cache
   module with the store data and address.
2. **WRITE_CACHE → WAIT_CACHE:** Cache performs lookup, finds hit, writes the
   64-bit word into the line at the block-offset position, sets `dirty=1`.
3. **WAIT_CACHE → COMPLETE_WRITE → IDLE:** After the cache confirms the write,
   L1D asserts `lsu_write_complete_out=1` for one cycle and returns the
   processor tag on `lsu_tag_out`.

**PLRU update:** Same as load hit.

**Dirty bit:** The line's dirty bit is set to 1. If it was already dirty, it
stays dirty.

### 5.3  Load Miss — Primary

**Precondition:** Load to an address whose block address is **not tracked by
any MSHR** (no existing miss to the same line). At least one MSHR is free.

**Sequence:**
1. **IDLE → READ_CACHE → WAIT_CACHE:** Cache reports a miss (no tag match).
   If the PLRU victim is dirty, the eviction path (§5.8) is taken first.
2. **WAIT_CACHE → CHECK_MSHR:** L1D scans MSHRs; no match found. Allocates a
   free MSHR, enqueues the request entry.
3. **CHECK_MSHR → SEND_REQ_LC:** L1D sends a read request (`lc_we_out=0`) to
   the LLC with the block address.
4. **SEND_REQ_LC → IDLE:** Once `lc_ready_in` is sampled high, the request is
   accepted. L1D returns to IDLE and is ready for new requests.

The load completes later when the LLC returns the line (see §5.7).

### 5.4  Store Miss — Primary

Same as §5.3 but with `we=1` in the MSHR entry and the store data recorded.
The LLC request is still a **read** (`lc_we_out=0`) — this is write-allocate
policy: fetch the line, then write the word into it.

### 5.5  Load Miss — Secondary

**Precondition:** Load to a block address that **is already tracked** by an
existing MSHR (a previous miss to the same line is outstanding).

**Without forwarding:**
If no store in the MSHR queue targets the same *exact byte address*, the load
is enqueued into that MSHR's queue. **No new LLC request is sent** — the
original miss request will return the line, and the load will be serviced
during MSHR playback (§5.7).

**With forwarding (store-to-load):**
If a store entry in the MSHR queue has the same *exact byte address* (full
22-bit match, not just block address), the load data is forwarded immediately
from the store's `data` field.

Sequence for forwarded case:
1. **CHECK_MSHR → SEND_RESP_HC:** Load data is taken from the matching store
   entry. The load is **not** enqueued.
2. **SEND_RESP_HC → IDLE:** `lsu_valid_out=1`, data and tag returned to LSU.

The most recent matching store in the queue wins if there are multiple writes
to the same address (scan from front to back, last match takes priority — or
if scanning uses `break` on first match, that entry must be the most recent
in program order).

### 5.6  Store Miss — Secondary

**Precondition:** Store to a block address already tracked by an MSHR.

The store is enqueued into the MSHR queue. **No new LLC request is sent.**
The store will be applied during MSHR playback after the line is installed.

> **Rationale for not sending duplicate LLC requests:** The primary miss
> already requested the block. Sending another read request for the same block
> is redundant and wastes LLC bandwidth. The MSHR exists precisely to coalesce
> multiple requests to the same line.

### 5.7  LLC Fill / MSHR Playback

When the LLC returns data (`lc_valid_in` asserted in IDLE), the L1D
prioritizes it over any pending LSU request.

**Sequence:**
1. **IDLE → WRITE_CACHE:** L1D passes the 512-bit fill data and address to the
   cache module for installation as a full cache line.
2. **WRITE_CACHE → CLEAR_MSHR:** Cache installs the line (valid=1, dirty=0,
   tag set). Now the L1D scans all MSHRs to find the one whose
   `no_offset_addr` matches the returning block address.
3. **CLEAR_MSHR:** Dequeue the front entry from the matching MSHR.
   - If it's a **store**: issue a word-write to the cache at the entry's full
     address, with the entry's store data. Transition to PROCESS_MSHR, then
     COMPLETE_WRITE. Assert `lsu_write_complete_out` and `lsu_tag_out`.
   - If it's a **load**: issue a word-read to the cache at the entry's full
     address. Transition to PROCESS_MSHR, then COMPLETE_READ. Assert
     `lsu_valid_out` with the read data and `lsu_tag_out`.
4. **COMPLETE_READ / COMPLETE_WRITE → CLEAR_MSHR or IDLE:** If the MSHR queue
   still has entries, loop back to CLEAR_MSHR to process the next one.
   Otherwise, return to IDLE.

**Important details:**
- Each MSHR entry is dequeued and serviced one at a time, in FIFO order.
- A store during playback sets `dirty=1` on the line.
- The processor tag returned with each completion is the tag stored in that
  MSHR entry — **not** the currently latched `lsu_tag_in_reg`.
- Multiple loads and stores to the same line are all serviced in sequence
  before the L1D returns to IDLE (unless the queue empties sooner).

### 5.8  Eviction

Eviction occurs when a miss requires installing a new line, but the PLRU
victim way in the target set is **valid and dirty**.

**Sequence:**
1. Cache module selects the victim via PLRU, detects dirty bit.
2. **EVICT_BLOCK (cache) → EVICT (L1D):** L1D sends the dirty line to the LLC:
   `lc_valid_out=1`, `lc_we_out=1`, `lc_addr_out` = victim's block address,
   `lc_value_out` = victim's 512-bit data.
3. **EVICT:** Held until `lc_ready_in` is sampled high (LLC accepted the
   writeback).
4. **EVICT → CLEAR_MSHR:** The writeback is complete. Now the new line can be
   installed and MSHR entries processed.

If the victim is **valid but clean**, no writeback is needed — the way is
simply overwritten.

If the victim is **invalid**, no eviction at all — the way is free.

### 5.9  Flush

When `flush_in` is asserted while the L1D is in IDLE:

1. All tag entries across all ways and sets have `valid` and `dirty` cleared.
2. All PLRU bits are cleared to 0.
3. All MSHR queues are reset (head=0, size=0).
4. The L1D returns to IDLE on the next cycle.

> **Note:** Flush does **not** write back dirty lines. It is a hard
> invalidation. If dirty data must be preserved, software must write-back
> explicitly before flushing.

### 5.10  Reset

Active-low synchronous reset (`rst_N_in=0`):
- All registers cleared to 0.
- State machine set to IDLE.
- `flush_in_reg` set to 1 (triggers a flush on the first active cycle).
- Tag array, data array, and PLRU state are all invalidated.
- MSHR queues are reset.

---

## 6  Priority and Arbitration

When both an LLC fill (`lc_valid_in`) and an LSU request (`lsu_valid_in`)
arrive in the same cycle while the L1D is IDLE:

> **LLC fill wins.** The fill is processed first. The LSU request is ignored
> (not latched), and `lsu_ready_out` may or may not be asserted that cycle
> depending on MSHR availability — but since the L1D transitions out of IDLE
> to service the fill, the LSU must retry on a subsequent cycle.

**Rationale:** Servicing the fill first unblocks any MSHR entries waiting on
that data, which frees MSHR slots and may allow the new LSU request to be
accepted sooner.

---

## 7  Back-Pressure and Flow Control

### 7.1  When `lsu_ready_out` is deasserted

The L1D deasserts `lsu_ready_out` (refuses new requests) when:

1. **Not in IDLE** — a transaction is in progress.
2. **All MSHRs are occupied** — every MSHR queue's front entry is valid. Even
   though the L1D is in IDLE, it cannot guarantee it can service a miss, so it
   blocks.

### 7.2  When `lc_ready_out` is deasserted

`lc_ready_out` is asserted when the L1D is in IDLE and `lc_valid_in` is
detected. At all other times it is 0. The LLC must hold its valid/data stable
until the L1D acknowledges.

### 7.3  MSHR Queue Full

If a secondary miss arrives and the matching MSHR's 16-entry queue is full,
the request **cannot be enqueued**. The L1D enters a blocked state. This is an
exceptional condition — under normal operation, the queue should not fill.

---

## 8  Data Coherency and Ordering

### 8.1  Store-to-Load Forwarding within MSHRs

When a load misses and its block address matches an existing MSHR:

- The MSHR queue is scanned for a store to the **exact same byte address**.
- If found, the store's data is forwarded directly to the load response —
  the load completes immediately without waiting for the LLC.
- If multiple stores to the same address exist in the queue, the **first
  match** found during the scan is used (the queue is scanned from index 0
  upward through the circular buffer).

### 8.2  Read-After-Write (Same Address, Both Miss)

If a store misses (primary) and a subsequent load to the same address arrives
before the fill:

1. The store is in the MSHR queue.
2. The load hits the secondary-miss path, scans the queue, finds the store.
3. The store's data is forwarded — the load completes immediately.

### 8.3  Write-After-Write (Same Address, Both Miss)

Two stores to the same address that both miss:

1. First store: primary miss, enqueued, LLC request sent.
2. Second store: secondary miss, enqueued behind the first.
3. On fill: both stores are played back in FIFO order. The second store's
   value is what remains in the cache (last-writer-wins).

### 8.4  Stores to Different Words in the Same Line

Multiple stores to different offsets within the same cache line, all missing:

1. First store: primary miss.
2. Subsequent stores: secondary misses, enqueued.
3. On fill: each store writes its word at its respective offset. All stores
   are reflected in the final line state.

---

## 9  Edge Cases and Corner Conditions

### 9.1  Miss Immediately Followed by Hit to Same Set, Different Tag

The first request misses and enters MSHR processing. The L1D returns to IDLE
after sending the LLC request. The second request arrives, hits a different
way in the same set. This is a normal hit — no conflict. PLRU is updated for
the hit way.

### 9.2  Two Misses to Different Lines in the Same Set

Both misses require MSHR allocation. Each gets its own MSHR. When fills
return, they may compete for the same PLRU victim way. The first fill installs
and updates PLRU. The second fill sees updated PLRU state and may select a
different victim.

### 9.3  Two Misses Exhaust All MSHRs

With `MSHR_COUNT=2`, two simultaneous outstanding misses to different blocks
fill all MSHRs. The L1D deasserts `lsu_ready_out` until at least one MSHR is
freed by a fill completion.

### 9.4  Eviction During MSHR Playback

If the fill triggers an eviction of a dirty line (because the PLRU victim in
the target set is dirty), the eviction writeback to the LLC must complete
before MSHR entries can be played back.

### 9.5  Fill Arrives for a Line That Was Subsequently Flushed

If a flush occurs after a miss request is sent to the LLC but before the fill
returns, the MSHR queues are cleared by the flush. When the fill arrives, no
MSHR entry will match the returning block address. The fill data is installed
into the cache, but no LSU completions are generated. The L1D returns to IDLE.

### 9.6  Back-to-Back Requests

The L1D can only accept a new request when in IDLE. After completing a hit
(load or store), it returns to IDLE and can accept the next request on the
very next cycle. There is no mandatory gap between transactions from the
LSU's perspective — just check `lsu_ready_out`.

### 9.7  Load to Uninitialized (Cold) Cache

All tag entries start invalid after reset/flush. Every access to a cold cache
is a compulsory miss. The PLRU victim selection finds an invalid way (no
eviction needed), and the line is installed from the LLC.

### 9.8  Address Alignment

All load/store addresses must be aligned to 8 bytes (bits `[2:0]` = 0). The
block offset bits `[5:3]` select which of the 8 words in the 64-byte line to
access. Behavior on unaligned access is undefined.

### 9.9  Simultaneous Enqueue and Dequeue on Same MSHR

The MSHR queue supports simultaneous enqueue and dequeue in the same cycle.
If both signals are asserted, size remains unchanged, the old head is removed,
and the new entry is placed at the tail.

### 9.10  MSHR Queue Wraps Around

The MSHR queue is a circular buffer with `head` and `size` pointers. Enqueue
position is `(head + size) % QUEUE_SIZE`. Dequeue increments `head` modulo
`QUEUE_SIZE`. The `full` and `empty` flags are derived from `size`.

---

## 10  Golden Model Contract

The C++ golden model must implement the following interface for the UVM
scoreboard:

### 10.1  State

The golden model maintains:

- **Cache state:** tag array (valid, dirty, tag per way per set), data array
  (512-bit line per way per set), PLRU bits (3 bits per set).
- **MSHR state:** 2 queues of up to 16 `mshr_entry` structs each.
- **Pending LLC requests:** track which block addresses have outstanding
  requests.
- **FSM state** (optional, for cycle-accurate mode): current state, latched
  inputs.

### 10.2  Transaction-Level Interface

For a **functional** (non-cycle-accurate) golden model suitable for
scoreboard checking:

```cpp
struct L1DResponse {
    bool     valid;           // true if this request produces an immediate completion
    bool     is_write;        // true if this was a store
    uint64_t addr;            // physical address (zero-extended to 64 bits)
    uint64_t data;            // load data (undefined for stores)
    uint16_t tag;             // processor tag
    bool     needs_llc_read;  // true if a miss triggered an LLC fetch
    bool     needs_eviction;  // true if eviction writeback is needed
    uint64_t evict_addr;      // eviction block address (if needs_eviction)
    uint64_t evict_data[8];   // eviction line data as 8 words (if needs_eviction)
};

// Process a request from the LSU. Returns immediate completion info.
L1DResponse process_request(uint64_t addr, uint64_t data,
                            uint16_t tag, bool is_write);

// Process a fill from the LLC. Returns a vector of completions
// (one per MSHR entry played back).
std::vector<L1DResponse> process_fill(uint64_t block_addr,
                                       uint64_t line_data[8]);

// Flush all state.
void flush();

// Reset to initial state.
void reset();
```

### 10.3  Scoreboard Usage

The UVM scoreboard operates as follows:

1. **On LSU request (monitor captures `lsu_valid_in && lsu_ready_out`):**
   Call `process_request()`. If `valid` is true (hit or MSHR forward), expect
   an immediate DUT completion with matching tag and data.

2. **On LLC fill (monitor captures `lc_valid_in && lc_ready_out`):**
   Call `process_fill()`. For each entry in the returned vector, expect a DUT
   completion with matching tag and data (for loads) or matching tag and
   write-complete (for stores).

3. **On DUT completion (monitor captures `lsu_valid_out`):**
   Match against expected completions by tag. Compare `lsu_value_out` for
   loads. Flag any unexpected or missing completions.

4. **On DUT eviction (monitor captures `lc_valid_out && lc_we_out`):**
   Verify the evicted address and data match what the golden model predicted.

### 10.4  What the Golden Model Must Track

| Aspect | How to model |
|---|---|
| Hit detection | Compare addr tag against tag_array[way][set] for all ways |
| Data read | Return `cache_data[hit_way][set]` word at offset |
| Data write | Modify `cache_data[hit_way][set]` word at offset, set dirty |
| PLRU update | Update plru_bits on every access (hit or install) |
| Victim selection | Scan plru_bits[set] for first 0 bit |
| Eviction check | If victim valid && dirty → record eviction |
| Line install | Write 512-bit line to victim way, set valid, clear dirty |
| MSHR allocate | On primary miss: find free MSHR, enqueue entry |
| MSHR coalesce | On secondary miss: enqueue into matching MSHR |
| MSHR forward | On secondary read: scan queue for store to same addr |
| MSHR playback | On fill: dequeue entries one by one, apply to cache |
| Flush | Clear all valid/dirty bits, PLRU, MSHR queues |

---

## 11  Latency Summary (Approximate)

These are not exact cycle counts but behavioral expectations for the golden
model and test planning.

| Operation | Behavior |
|---|---|
| Load hit | Completes without LLC interaction |
| Store hit | Completes without LLC interaction |
| Load miss (primary) | Completes after LLC fill + MSHR playback |
| Store miss (primary) | Write-complete after LLC fill + MSHR playback |
| Secondary miss (no fwd) | Completes during MSHR playback of the matching fill |
| Secondary miss (fwd) | Completes immediately (like a hit) |
| Eviction | Adds LLC writeback latency before fill can be installed |

---

## 12  Known RTL Divergences from This Spec

The following are areas where the current RTL (`l1_data_cache.sv`) may not
yet match this specification. These should be resolved:

1. **`lsu_write_complete_out` never asserted.** The combinational signal is
   initialized to 0 and is never set to 1. Store completions are currently
   silent. **Fix:** Assert in COMPLETE_WRITE state and for write-hit
   completion.

2. **`COMPLETE_WRITE` has no case handler.** Falls through to `default →
   IDLE`. Should explicitly assert `lsu_write_complete_out` and
   `lsu_tag_out`, then transition to CLEAR_MSHR or IDLE.

3. **`lsu_tag_out_comb` overridden after case statement (line 537).** The
   assignment `lsu_tag_out_comb = (cur_state == IDLE) ? lsu_tag_in :
   lsu_tag_in_reg` runs unconditionally, clobbering the tag set by
   CLEAR_MSHR for MSHR playback completions. **Fix:** Only apply the default
   tag assignment when the case statement hasn't explicitly set it, or remove
   the override and set the tag in each relevant state.

4. **Secondary miss stores send redundant LLC requests.** In CHECK_MSHR, when
   a store hits a secondary miss, the FSM transitions to SEND_REQ_LC. The
   primary miss already requested this block. **Fix:** Transition to IDLE
   instead, same as secondary miss loads that get enqueued.

5. **Dead states.** `WAIT_CACHE_READ` and `WAIT_MSHR` are defined in the enum
   but have no case handlers and are never transitioned to. **Fix:** Remove
   from enum.

6. **Write-hit 5-cycle delay.** The WAIT_CACHE else-branch counts down from 5
   before going to COMPLETE_WRITE. This artificial delay may not be
   intentional. **Clarify:** Is the delay needed for write-through latency
   or is it vestigial?
