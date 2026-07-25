#include "bareruby_runtime.h"

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>

void bareruby_puts_int32(int32_t value) {
    printf("%d\n", (int)value);
}

void bareruby_puts_int64(int64_t value) {
    printf("%lld\n", (long long)value);
}

void bareruby_puts_string(const char *value) {
    printf("%s\n", value);
}

const char *bareruby_bool_to_s(bool value) {
    return value ? "true" : "false";
}

void bareruby_puts_bool(bool value) {
    printf("%s\n", bareruby_bool_to_s(value));
}

void bareruby_printf(const char *format, ...) {
    va_list arguments;
    va_start(arguments, format);
    vprintf(format, arguments);
    va_end(arguments);
}

/* Fixed is Q16.16 held in an int32_t. Narrowing saturates rather than wrapping,
   and the half LSB is added before the shift so rounding happens first. */
static int32_t bareruby_fixed_saturate(int64_t value) {
    if (value > (int64_t)INT32_MAX) {
        return INT32_MAX;
    }
    if (value < (int64_t)INT32_MIN) {
        return INT32_MIN;
    }
    return (int32_t)value;
}

int32_t bareruby_int32_to_fixed(int32_t value) {
    return (int32_t)((uint32_t)value << 16);
}

int32_t bareruby_fixed_to_i32(int32_t value) {
    return value >= 0 ? (value >> 16) : -((-(int64_t)value) >> 16);
}

int32_t bareruby_fixed_mul(int32_t left, int32_t right) {
    int64_t product = (int64_t)left * (int64_t)right;
    return bareruby_fixed_saturate((product + (1 << 15)) >> 16);
}

int32_t bareruby_fixed_div(int32_t left, int32_t right) {
    if (right == 0) {
        return left < 0 ? INT32_MIN : INT32_MAX;
    }
    int64_t numerator = (int64_t)left << 16;
    int64_t half = (int64_t)(right < 0 ? -right : right) / 2;
    numerator += (numerator < 0) ? -half : half;
    return bareruby_fixed_saturate(numerator / right);
}

static const uint32_t BARERUBY_FIXED_POWERS[6] = { 1u, 10u, 100u, 1000u, 10000u, 100000u };

/* Shortest decimal that parses back to the same Q16.16 value. Five fraction
   digits always suffice, so try one digit first and stop at the first match. */
const char *bareruby_fixed_to_s(int32_t value) {
    static char buffer[24];
    int64_t magnitude = value < 0 ? -(int64_t)value : (int64_t)value;
    uint32_t whole = (uint32_t)(magnitude >> 16);
    uint32_t fraction = (uint32_t)(magnitude & 0xFFFF);

    for (int length = 1; length <= 5; ++length) {
        uint32_t power = BARERUBY_FIXED_POWERS[length];
        uint32_t digits = (uint32_t)(((uint64_t)fraction * power + 32768u) >> 16);
        if (digits >= power) {
            continue;
        }
        uint32_t restored = (uint32_t)((((uint64_t)digits << 16) + power / 2u) / power);
        if (restored == fraction) {
            snprintf(buffer, sizeof(buffer), "%s%u.%0*u",
                     value < 0 ? "-" : "", whole, length, digits);
            return buffer;
        }
    }

    snprintf(buffer, sizeof(buffer), "%s%u.%05u", value < 0 ? "-" : "", whole,
             (uint32_t)(((uint64_t)fraction * 100000u + 32768u) >> 16));
    return buffer;
}

void bareruby_puts_fixed(int32_t value) {
    printf("%s\n", bareruby_fixed_to_s(value));
}
