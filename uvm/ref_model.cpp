#include "ref_model.h"
#include <map>
#include <iostream>

static std::map<uint64_t, uint64_t> ref_mem;

extern "C" {

void mem_write(uint64_t addr, uint64_t data) {
    uint64_t aligned_addr = addr & ~0x7ULL;
    ref_mem[aligned_addr] = data;
}

uint64_t mem_read(uint64_t addr) {
    uint64_t aligned_addr = addr & ~0x7ULL;
    if (ref_mem.find(aligned_addr) == ref_mem.end()) {
        // Default value: each 8-byte aligned address contains its own address
        // This matches the LLC responder behavior
        return aligned_addr;
    }
    return ref_mem[aligned_addr];
}

void mem_reset() {
    ref_mem.clear();
}

} // extern "C"
