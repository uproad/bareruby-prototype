#include "bareruby_runtime.h"

#include <stdio.h>

void bareruby_puts_int32(int32_t value) {
    printf("%d\n", (int)value);
}

void bareruby_puts_int64(int64_t value) {
    printf("%lld\n", (long long)value);
}
