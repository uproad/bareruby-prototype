#ifndef BARERUBY_RUNTIME_H
#define BARERUBY_RUNTIME_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void bareruby_puts_int32(int32_t value);
void bareruby_puts_int64(int64_t value);

#ifdef __cplusplus
}
#endif

#endif
