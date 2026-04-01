#ifndef REF_MODEL_H
#define REF_MODEL_H

#include <stdint.h>
#include <map>

#ifdef __cplusplus
extern "C" {
#endif

void mem_write(uint64_t addr, uint64_t data);
uint64_t mem_read(uint64_t addr);
void mem_reset();

#ifdef __cplusplus
}
#endif

#endif // REF_MODEL_H
