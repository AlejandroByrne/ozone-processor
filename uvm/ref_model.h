#ifndef REF_MODEL_H
#define REF_MODEL_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Full cache-aware golden model API
void l1d_model_reset();

// Process a request from the LSU side.
// Returns 1 if immediate completion expected (hit or MSHR forward), 0 if miss.
int l1d_model_request(int addr, long long data, int tag, int is_write);

// Process an LLC fill accepted by the DUT.
// Returns the number of MSHR playback completions queued.
int l1d_model_fill(int block_addr,
    long long w0, long long w1, long long w2, long long w3,
    long long w4, long long w5, long long w6, long long w7);

// Pop the next expected completion from the queue.
// Returns 1 if there was one, 0 if empty.
int l1d_model_pop_completion(int *out_tag, long long *out_data, int *out_is_write);

// Number of pending expected completions.
int l1d_model_pending_count();

// Legacy flat-map API (kept for backward compat)
void mem_write(uint64_t addr, uint64_t data);
uint64_t mem_read(uint64_t addr);
void mem_reset();

#ifdef __cplusplus
}
#endif

#endif // REF_MODEL_H
