#include "ref_model.h"
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <deque>
#include <queue>
#include <map>

// Cache parameters — must match l1d_pkg.sv
static const int A = 3;
static const int B = 64;
static const int C = 1536;
static const int PADDR_BITS = 22;
static const int MSHR_COUNT = 2;
static const int MSHR_QUEUE_SIZE = 16;
static const int WORDS_PER_LINE = B / 8;        // 8
static const int NUM_BLOCKS = C / B;             // 24
static const int NUM_SETS = NUM_BLOCKS / A;      // 8
static const int BLOCK_OFFSET_BITS = 6;          // log2(64)
static const int SET_INDEX_BITS = 3;             // log2(8)
static const int TAG_BITS = PADDR_BITS - SET_INDEX_BITS - BLOCK_OFFSET_BITS; // 13
static const uint32_t ADDR_MASK = (1u << PADDR_BITS) - 1;

// ---------------------------------------------------------------------------
// Address helpers
// ---------------------------------------------------------------------------
static inline uint16_t get_tag(uint32_t addr) {
    return (addr >> (SET_INDEX_BITS + BLOCK_OFFSET_BITS)) & ((1 << TAG_BITS) - 1);
}
static inline uint8_t get_set(uint32_t addr) {
    return (addr >> BLOCK_OFFSET_BITS) & ((1 << SET_INDEX_BITS) - 1);
}
static inline uint8_t get_word(uint32_t addr) {
    return (addr >> 3) & 0x7;
}
static inline uint32_t get_block_addr(uint32_t addr) {
    return addr >> BLOCK_OFFSET_BITS;
}

// ---------------------------------------------------------------------------
// Data types
// ---------------------------------------------------------------------------
struct TagEntry {
    bool valid;
    bool dirty;
    uint16_t tag;
};

struct MSHREntry {
    uint32_t paddr;
    uint32_t block_addr;
    bool     we;
    uint64_t data;
    uint16_t proc_tag;
};

struct ExpectedCompletion {
    uint16_t tag;
    uint64_t data;
    bool     is_write;
};

struct MSHRQueue {
    std::deque<MSHREntry> entries;
    int victim_way;           // way chosen for this miss
    bool active() const { return !entries.empty(); }
    uint32_t block() const { return entries.empty() ? 0 : entries.front().block_addr; }
};

// ---------------------------------------------------------------------------
// Model state
// ---------------------------------------------------------------------------
static TagEntry  tag_array[A][NUM_SETS];
static uint64_t  data_array[A][NUM_SETS][WORDS_PER_LINE];
static uint8_t   plru_bits[NUM_SETS];           // one bit per way
static MSHRQueue mshr[MSHR_COUNT];
static std::queue<ExpectedCompletion> completions;

// Legacy flat map
static std::map<uint64_t, uint64_t> legacy_mem;

// ---------------------------------------------------------------------------
// PLRU helpers
// ---------------------------------------------------------------------------
static int plru_victim(uint8_t set) {
    uint8_t b = plru_bits[set];
    if (!(b & 1)) return 0;
    if (!(b & 2)) return 1;
    return 2;
}

static void plru_update(uint8_t set, int way) {
    plru_bits[set] |= (1 << way);
    if ((plru_bits[set] & 0x7) == 0x7)
        plru_bits[set] = (uint8_t)(1 << way);
}

// ---------------------------------------------------------------------------
// LLC-generated data  (matches llc_responder.sv generate_cacheline)
// ---------------------------------------------------------------------------
static uint64_t llc_default_word(uint32_t block_aligned_addr, int word_idx) {
    uint64_t base = (uint64_t)(block_aligned_addr & ~0x3Fu);
    return base + (uint64_t)(word_idx * 8);
}

// ---------------------------------------------------------------------------
// Cache lookup — returns hit way or -1
// ---------------------------------------------------------------------------
static int cache_lookup(uint8_t set, uint16_t ctag) {
    for (int w = 0; w < A; w++) {
        if (tag_array[w][set].valid && tag_array[w][set].tag == ctag)
            return w;
    }
    return -1;
}

// ---------------------------------------------------------------------------
// Queue a completion
// ---------------------------------------------------------------------------
static void push_completion(uint16_t tag, uint64_t data, bool is_write) {
    ExpectedCompletion c;
    c.tag = tag;
    c.data = data;
    c.is_write = is_write;
    completions.push(c);
}

// ---------------------------------------------------------------------------
// Install a full cache line
// ---------------------------------------------------------------------------
static void install_line(int way, uint8_t set, uint16_t ctag,
                         const uint64_t line[WORDS_PER_LINE], bool dirty) {
    tag_array[way][set].valid = true;
    tag_array[way][set].dirty = dirty;
    tag_array[way][set].tag   = ctag;
    for (int i = 0; i < WORDS_PER_LINE; i++)
        data_array[way][set][i] = line[i];
    plru_update(set, way);
}

// ===================================================================
// PUBLIC API
// ===================================================================

extern "C" {

void l1d_model_reset() {
    memset(tag_array, 0, sizeof(tag_array));
    memset(data_array, 0, sizeof(data_array));
    memset(plru_bits, 0, sizeof(plru_bits));
    for (int i = 0; i < MSHR_COUNT; i++) {
        mshr[i].entries.clear();
        mshr[i].victim_way = 0;
    }
    while (!completions.empty()) completions.pop();
    legacy_mem.clear();
}

// -----------------------------------------------------------------
int l1d_model_request(int addr_i, long long data_i, int tag_i, int is_write_i) {
    uint32_t addr   = (uint32_t)addr_i & ADDR_MASK;
    uint64_t sdata  = (uint64_t)data_i;
    uint16_t ptag   = (uint16_t)(tag_i & 0x3FF);
    bool     we     = (is_write_i != 0);

    uint8_t  set    = get_set(addr);
    uint16_t ctag   = get_tag(addr);
    uint8_t  word   = get_word(addr);
    uint32_t baddr  = get_block_addr(addr);

    // Update legacy map immediately (stores are immediately visible there)
    if (we) legacy_mem[addr & ~0x7ULL] = sdata;

    // ---- Cache lookup ----
    int hit_way = cache_lookup(set, ctag);

    if (hit_way >= 0) {
        // ***  HIT  ***
        plru_update(set, hit_way);

        if (we) {
            data_array[hit_way][set][word] = sdata;
            tag_array[hit_way][set].dirty = true;
            push_completion(ptag, 0, true);          // store completion
        } else {
            uint64_t rdata = data_array[hit_way][set][word];
            push_completion(ptag, rdata, false);      // load completion
        }
        return 1; // immediate
    }

    // ---- MISS — check MSHRs for secondary miss ----
    int found_mshr = -1;
    for (int i = 0; i < MSHR_COUNT; i++) {
        if (mshr[i].active() && mshr[i].block() == baddr) {
            found_mshr = i;
            break;
        }
    }

    if (found_mshr >= 0) {
        // *** SECONDARY MISS ***
        int m = found_mshr;

        if (we) {
            // Secondary store: enqueue, no immediate completion
            if ((int)mshr[m].entries.size() < MSHR_QUEUE_SIZE) {
                MSHREntry e = {addr, baddr, true, sdata, ptag};
                mshr[m].entries.push_back(e);
            }
            return 0;
        } else {
            // Secondary load: check for store-to-load forwarding
            for (int i = (int)mshr[m].entries.size() - 1; i >= 0; i--) {
                if (mshr[m].entries[i].we && mshr[m].entries[i].paddr == addr) {
                    // Forward from store in MSHR
                    push_completion(ptag, mshr[m].entries[i].data, false);
                    return 1; // immediate via forwarding
                }
            }
            // No forwarding — enqueue
            if ((int)mshr[m].entries.size() < MSHR_QUEUE_SIZE) {
                MSHREntry e = {addr, baddr, false, 0, ptag};
                mshr[m].entries.push_back(e);
            }
            return 0;
        }
    }

    // *** PRIMARY MISS — allocate new MSHR ***
    int free_mshr = -1;
    for (int i = 0; i < MSHR_COUNT; i++) {
        if (!mshr[i].active()) { free_mshr = i; break; }
    }
    if (free_mshr < 0) {
        // All MSHRs full — should not happen if DUT back-pressures correctly
        fprintf(stderr, "[GOLDEN] ERROR: no free MSHR for primary miss addr=0x%x\n", addr);
        return 0;
    }

    int m = free_mshr;

    // Select victim via PLRU
    int vway = plru_victim(set);
    mshr[m].victim_way = vway;

    // Evict victim if dirty  (we don't verify eviction data in this iteration,
    // but we invalidate the way so the model stays consistent)
    if (tag_array[vway][set].valid && tag_array[vway][set].dirty) {
        // Eviction happens — data written back to LLC responder.
        // Update legacy_mem with dirty line data so future reads are correct.
        uint32_t victim_block = ((uint32_t)tag_array[vway][set].tag
                                 << SET_INDEX_BITS | set);
        uint32_t victim_base = victim_block << BLOCK_OFFSET_BITS;
        for (int w = 0; w < WORDS_PER_LINE; w++) {
            uint64_t vaddr = (uint64_t)(victim_base + w * 8);
            legacy_mem[vaddr] = data_array[vway][set][w];
        }
    }

    // Invalidate victim way (fill will install later)
    tag_array[vway][set].valid = false;

    // Enqueue request into MSHR
    MSHREntry e = {addr, baddr, we, sdata, ptag};
    mshr[m].entries.push_back(e);

    return 0; // deferred
}

// -----------------------------------------------------------------
int l1d_model_fill(int block_addr_i,
                   long long w0, long long w1, long long w2, long long w3,
                   long long w4, long long w5, long long w6, long long w7) {
    uint32_t baddr = (uint32_t)block_addr_i;
    uint64_t line[WORDS_PER_LINE] = {
        (uint64_t)w0, (uint64_t)w1, (uint64_t)w2, (uint64_t)w3,
        (uint64_t)w4, (uint64_t)w5, (uint64_t)w6, (uint64_t)w7
    };

    // Find matching MSHR
    int found = -1;
    for (int i = 0; i < MSHR_COUNT; i++) {
        if (mshr[i].active() && mshr[i].block() == baddr) {
            found = i;
            break;
        }
    }
    if (found < 0) {
        // No MSHR match — fill arrived but MSHR was flushed or already cleared.
        // Install the line anyway (the DUT does this).
        uint32_t addr0 = baddr << BLOCK_OFFSET_BITS;
        uint8_t  set   = get_set(addr0);
        uint16_t ctag  = get_tag(addr0);
        int vway = plru_victim(set);
        install_line(vway, set, ctag, line, false);
        return 0;
    }

    int m = found;
    int vway = mshr[m].victim_way;
    uint32_t addr0 = baddr << BLOCK_OFFSET_BITS;
    uint8_t  set   = get_set(addr0);
    uint16_t ctag  = get_tag(addr0);

    // Step 1: Install the full fill line (clean)
    install_line(vway, set, ctag, line, false);

    // Step 2: Play back MSHR entries in FIFO order
    int count = 0;
    while (!mshr[m].entries.empty()) {
        MSHREntry e = mshr[m].entries.front();
        mshr[m].entries.pop_front();

        uint8_t ew = get_word(e.paddr);

        if (e.we) {
            // Store: apply to cache, mark dirty
            data_array[vway][set][ew] = e.data;
            tag_array[vway][set].dirty = true;
            // Also update legacy map
            legacy_mem[e.paddr & ~0x7ULL] = e.data;
            push_completion(e.proc_tag, 0, true);
        } else {
            // Load: read from cache (line was just installed, possibly modified by earlier stores)
            uint64_t rdata = data_array[vway][set][ew];
            push_completion(e.proc_tag, rdata, false);
        }
        count++;
    }

    return count;
}

// -----------------------------------------------------------------
int l1d_model_pop_completion(int *out_tag, long long *out_data, int *out_is_write) {
    if (completions.empty()) return 0;
    ExpectedCompletion c = completions.front();
    completions.pop();
    *out_tag = (int)c.tag;
    *out_data = (long long)c.data;
    *out_is_write = c.is_write ? 1 : 0;
    return 1;
}

// -----------------------------------------------------------------
int l1d_model_pending_count() {
    return (int)completions.size();
}

// -----------------------------------------------------------------
// Legacy flat-map API
// -----------------------------------------------------------------
void mem_write(uint64_t addr, uint64_t data) {
    legacy_mem[addr & ~0x7ULL] = data;
}

uint64_t mem_read(uint64_t addr) {
    uint64_t aligned = addr & ~0x7ULL;
    auto it = legacy_mem.find(aligned);
    if (it != legacy_mem.end()) return it->second;
    return aligned; // default: address-as-data
}

void mem_reset() {
    legacy_mem.clear();
}

} // extern "C"
