#ifndef BARERUBY_RUNTIME_H
#define BARERUBY_RUNTIME_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

void bareruby_puts_int32(int32_t value);
void bareruby_puts_int64(int64_t value);
void bareruby_puts_string(const char *value);
void bareruby_puts_bool(bool value);
void bareruby_puts_fixed(int32_t value);
const char *bareruby_bool_to_s(bool value);
const char *bareruby_fixed_to_s(int32_t value);
int32_t bareruby_int32_to_fixed(int32_t value);
int32_t bareruby_fixed_to_i32(int32_t value);
int32_t bareruby_fixed_mul(int32_t left, int32_t right);
int32_t bareruby_fixed_div(int32_t left, int32_t right);
void bareruby_printf(const char *format, ...);

#ifdef __cplusplus
}
#endif

#endif
