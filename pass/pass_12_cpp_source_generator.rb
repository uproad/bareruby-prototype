# frozen_string_literal: true

module BareRubyProt
  module Pass
    class CppSourceGenerator
      PUTS_FUNCTIONS = %i[
        bareruby_puts_int32 bareruby_puts_int64 bareruby_puts_string bareruby_puts_bool
        bareruby_puts_fixed bareruby_printf
      ].freeze

      RUNTIME_HEADER = <<~CPP
        #ifndef BARERUBY_RUNTIME_H
        #define BARERUBY_RUNTIME_H

        #include <stdbool.h>
        #include <stdint.h>

        typedef struct {
            unsigned char *base;
            int32_t capacity;
            int32_t used;
        } bareruby_arena_t;

        /* A variable-length string: the bytes, how many of them are in use, how many the
           block holds, and the region the next block will come from. The handle lives in
           that region too, so a program never holds one of these by value — it holds the
           address the region handed out, and the generated code reads no field of it. */
        typedef struct {
            bareruby_arena_t *arena;
            char *bytes;
            int32_t length;
            int32_t capacity;
        } bareruby_string_t;

        #ifdef __cplusplus
        extern "C" {
        #endif

        void bareruby_arena_init(bareruby_arena_t *self, unsigned char *storage, int32_t capacity);
        void *bareruby_arena_alloc(bareruby_arena_t *self, int32_t bytes);
        void bareruby_arena_reset(bareruby_arena_t *self);
        bareruby_string_t *bareruby_string_new(bareruby_arena_t *arena, const char *initial);
        bareruby_string_t *bareruby_string_format(bareruby_arena_t *arena, const char *format, ...);
        bareruby_string_t *bareruby_string_append(bareruby_string_t *self, const char *text);
        bareruby_string_t *bareruby_string_append_bytes(
            bareruby_string_t *self, const char *bytes, int32_t length);
        bareruby_string_t *bareruby_string_append_byte(bareruby_string_t *self, int32_t byte);
        bareruby_string_t *bareruby_string_append_format(bareruby_string_t *self, const char *format, ...);
        bareruby_string_t *bareruby_string_concat(bareruby_string_t *self, const char *text);
        bareruby_string_t *bareruby_string_dup(bareruby_string_t *self);
        const char *bareruby_string_bytes(bareruby_string_t *self);
        int32_t bareruby_string_length(bareruby_string_t *self);
        bool bareruby_string_equal(bareruby_string_t *self, const char *text);
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
        void bareruby_panic(const char *message);
        void bareruby_throw(const char *message);
        void bareruby_format(char *buffer, int32_t capacity, const char *format, ...);

        #ifdef __cplusplus
        }

        /* What releases an arena block's region. The destructor runs on the way out of
           the scope, so an exception leaving the block releases the region exactly as
           falling off its end does. A long-lived arena takes no guard: nothing but reset
           releases it. */
        struct bareruby_arena_scope {
            bareruby_arena_t *arena;
            ~bareruby_arena_scope() { bareruby_arena_reset(arena); }
        };
        #endif

        #endif
      CPP

      # A region allocator: allocation is a bump of one pointer, release is that pointer
      # going back, and the storage each arena hands out belongs to the site that declared
      # it. Running out is a panic rather than a growth, which is what keeps allocation
      # O(1) and the RAM an arena costs known before the program runs.
      RUNTIME_ARENA_SOURCE = <<~CPP
        #include "bareruby_runtime.h"

        #include <stdint.h>

        /* Eight bytes covers every alignment the language has, Int64 and Fixed included,
           so one rounding rule serves every allocation. */
        static const int32_t BARERUBY_ARENA_ALIGNMENT = 8;

        void bareruby_arena_init(bareruby_arena_t *self, unsigned char *storage, int32_t capacity) {
            self->base = storage;
            self->capacity = capacity;
            self->used = 0;
        }

        void *bareruby_arena_alloc(bareruby_arena_t *self, int32_t bytes) {
            int32_t start = (self->used + BARERUBY_ARENA_ALIGNMENT - 1) & ~(BARERUBY_ARENA_ALIGNMENT - 1);
            if (bytes < 0 || start > self->capacity - bytes) {
                bareruby_panic("arena is full");
            }
            self->used = start + bytes;
            return self->base + start;
        }

        void bareruby_arena_reset(bareruby_arena_t *self) {
            self->used = 0;
        }
      CPP

      # The string the first two layers of the memory model cannot hold: its length is a
      # run-time value and it grows, so both its bytes and its handle come from a region.
      # Growing is a bigger block and a copy into it, and the block it leaves behind stays
      # until the region is released — an arena has no free.
      RUNTIME_STRING_SOURCE = <<~CPP
        #include "bareruby_runtime.h"

        #include <stdarg.h>
        #include <stdint.h>
        #include <stdio.h>
        #include <string.h>

        /* Room to grow into, so a string appended to a few bytes at a time does not take a
           fresh block every time. */
        static const int32_t BARERUBY_STRING_MINIMUM_CAPACITY = 16;

        static int32_t bareruby_string_capacity_for(int32_t length) {
            int32_t capacity = BARERUBY_STRING_MINIMUM_CAPACITY;
            while (capacity < length + 1) {
                capacity *= 2;
            }
            return capacity;
        }

        /* The handle comes from the region as well as the bytes, so it outlives the scope
           that created it and every binding is the address of the one string. */
        static bareruby_string_t *bareruby_string_allocate(bareruby_arena_t *arena, int32_t length) {
            bareruby_string_t *self =
                (bareruby_string_t *)bareruby_arena_alloc(arena, (int32_t)sizeof(bareruby_string_t));
            self->arena = arena;
            self->capacity = bareruby_string_capacity_for(length);
            self->bytes = (char *)bareruby_arena_alloc(arena, self->capacity);
            self->bytes[0] = '\\0';
            self->length = 0;
            return self;
        }

        static void bareruby_string_reserve(bareruby_string_t *self, int32_t length) {
            if (length + 1 <= self->capacity) {
                return;
            }
            int32_t capacity = bareruby_string_capacity_for(length);
            char *bytes = (char *)bareruby_arena_alloc(self->arena, capacity);
            memcpy(bytes, self->bytes, (size_t)self->length + 1);
            self->bytes = bytes;
            self->capacity = capacity;
        }

        bareruby_string_t *bareruby_string_new(bareruby_arena_t *arena, const char *initial) {
            int32_t length = (int32_t)strlen(initial);
            bareruby_string_t *self = bareruby_string_allocate(arena, length);
            memcpy(self->bytes, initial, (size_t)length + 1);
            self->length = length;
            return self;
        }

        bareruby_string_t *bareruby_string_append(bareruby_string_t *self, const char *text) {
            int32_t length = (int32_t)strlen(text);
            return bareruby_string_append_bytes(self, text, length);
        }

        bareruby_string_t *bareruby_string_append_bytes(
            bareruby_string_t *self, const char *bytes, int32_t length) {
            bareruby_string_reserve(self, self->length + length);
            memcpy(self->bytes + self->length, bytes, (size_t)length);
            self->length += length;
            self->bytes[self->length] = '\\0';
            return self;
        }

        bareruby_string_t *bareruby_string_append_byte(bareruby_string_t *self, int32_t byte) {
            bareruby_string_reserve(self, self->length + 1);
            self->bytes[self->length] = (char)byte;
            self->length += 1;
            self->bytes[self->length] = '\\0';
            return self;
        }

        /* vsnprintf answers how long a rendering is before writing it, so an interpolation
           that lands in a string needs no compile-time estimate of its parts. */
        bareruby_string_t *bareruby_string_format(bareruby_arena_t *arena, const char *format, ...) {
            va_list arguments;
            va_start(arguments, format);
            int32_t length = (int32_t)vsnprintf(NULL, 0, format, arguments);
            va_end(arguments);

            bareruby_string_t *self = bareruby_string_allocate(arena, length);
            va_start(arguments, format);
            vsnprintf(self->bytes, (size_t)self->capacity, format, arguments);
            va_end(arguments);
            self->length = length;
            return self;
        }

        bareruby_string_t *bareruby_string_append_format(bareruby_string_t *self, const char *format, ...) {
            va_list arguments;
            va_start(arguments, format);
            int32_t length = (int32_t)vsnprintf(NULL, 0, format, arguments);
            va_end(arguments);

            bareruby_string_reserve(self, self->length + length);
            va_start(arguments, format);
            vsnprintf(self->bytes + self->length, (size_t)(self->capacity - self->length), format, arguments);
            va_end(arguments);
            self->length += length;
            return self;
        }

        /* + answers a new string, as Ruby does, taken from the region the receiver's own
           bytes came from. */
        bareruby_string_t *bareruby_string_concat(bareruby_string_t *self, const char *text) {
            bareruby_string_t *result =
                bareruby_string_allocate(self->arena, self->length + (int32_t)strlen(text));
            bareruby_string_append(result, self->bytes);
            return bareruby_string_append(result, text);
        }

        bareruby_string_t *bareruby_string_dup(bareruby_string_t *self) {
            return bareruby_string_new(self->arena, self->bytes);
        }

        const char *bareruby_string_bytes(bareruby_string_t *self) {
            return self->bytes;
        }

        int32_t bareruby_string_length(bareruby_string_t *self) {
            return self->length;
        }

        bool bareruby_string_equal(bareruby_string_t *self, const char *text) {
            return strcmp(self->bytes, text) == 0;
        }
      CPP

      # Fixed arithmetic is pure and has no stdout to depend on, so it is linked into every
      # build. The rest of the runtime needs stdio and is only linked when a stdout channel
      # exists, which is why the two are separate translation units.
      RUNTIME_FIXED_SOURCE = <<~CPP
        #include "bareruby_runtime.h"

        #include <stdint.h>

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
      CPP

      # A throw expression pulls in the C++ ABI, and with it the terminate handler's name
      # demangler and malloc: about 60 KB on an rp2040, whether or not anything throws.
      # --gc-sections cannot reach it, so this is its own translation unit and is linked
      # only into programs that actually raise.
      RUNTIME_THROW_SOURCE = <<~CPP
        #include "bareruby_runtime.h"

        void bareruby_throw(const char *message) {
            throw message;
        }
      CPP

      RUNTIME_STDIO_SOURCE = <<~CPP
        #include "bareruby_runtime.h"

        #include <stdarg.h>
        #include <stdbool.h>
        #include <stdint.h>
        #include <stdio.h>
        #include <stdlib.h>

        void bareruby_puts_int32(int32_t value) {
            printf("%d\\n", (int)value);
        }

        void bareruby_puts_int64(int64_t value) {
            printf("%lld\\n", (long long)value);
        }

        void bareruby_puts_string(const char *value) {
            printf("%s\\n", value);
        }

        const char *bareruby_bool_to_s(bool value) {
            return value ? "true" : "false";
        }

        void bareruby_puts_bool(bool value) {
            printf("%s\\n", bareruby_bool_to_s(value));
        }

        void bareruby_printf(const char *format, ...) {
            va_list arguments;
            va_start(arguments, format);
            vprintf(format, arguments);
            va_end(arguments);
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
            printf("%s\\n", bareruby_fixed_to_s(value));
        }

        /* A panic stops immediately without unwinding: stdout is flushed, the message
           goes to fd2, and the process exits 1. */
        void bareruby_panic(const char *message) {
            fflush(stdout);
            fprintf(stderr, "panic: %s\\n", message);
            exit(1);
        }

        /* The buffer is sized at compile time from the widest rendering of each part, so
           this never allocates and never grows. */
        void bareruby_format(char *buffer, int32_t capacity, const char *format, ...) {
            va_list arguments;
            va_start(arguments, format);
            vsnprintf(buffer, (size_t)capacity, format, arguments);
            va_end(arguments);
        }
      CPP

      BINDING_HEADER = <<~CPP
        #ifndef BARERUBY_BINDING_H
        #define BARERUBY_BINDING_H

        #include <stdbool.h>
        #include <stdint.h>
        #include "bareruby_runtime.h"

        #ifdef __cplusplus
        extern "C" {
        #endif

        typedef struct {
            int32_t pin;
            int32_t params;
        } bareruby_gpio_t;

        typedef struct {
            int32_t pin;
            int32_t slice;
            int32_t frequency;
        } bareruby_pwm_t;

        typedef struct {
            int32_t id;
            int32_t baud;
            int32_t parity;
        } bareruby_uart_t;

        typedef struct {
            int32_t id;
            int32_t frequency;
        } bareruby_i2c_t;

        typedef struct {
            int32_t pin;
            int32_t channel;
        } bareruby_adc_t;

        void bareruby_startup(void);

        void bareruby_gpio_init(bareruby_gpio_t *self, int32_t pin, int32_t params);
        void bareruby_gpio_write(bareruby_gpio_t *self, int32_t value);
        int32_t bareruby_gpio_read(bareruby_gpio_t *self);
        bool bareruby_gpio_high(bareruby_gpio_t *self);
        bool bareruby_gpio_low(bareruby_gpio_t *self);

        void bareruby_pwm_init(bareruby_pwm_t *self, int32_t pin, int32_t frequency, int32_t duty);
        void bareruby_pwm_frequency(bareruby_pwm_t *self, int32_t frequency);
        void bareruby_pwm_period_us(bareruby_pwm_t *self, int32_t period_us);
        void bareruby_pwm_duty(bareruby_pwm_t *self, int32_t duty);
        void bareruby_pwm_pulse_width_us(bareruby_pwm_t *self, int32_t pulse_width_us);

        void bareruby_uart_init(bareruby_uart_t *self, int32_t id, int32_t baud, int32_t parity);
        int32_t bareruby_uart_write(bareruby_uart_t *self, const char *value);
        void bareruby_uart_puts(bareruby_uart_t *self, const char *value);
        void bareruby_uart_printf(bareruby_uart_t *self, const char *format, ...);
        bareruby_string_t *bareruby_uart_read(
            bareruby_uart_t *self, bareruby_arena_t *arena, int32_t length);
        bareruby_string_t *bareruby_uart_gets(bareruby_uart_t *self, bareruby_arena_t *arena);
        int32_t bareruby_uart_bytes_available(bareruby_uart_t *self);
        bool bareruby_uart_can_read_line(bareruby_uart_t *self);
        void bareruby_uart_flush(bareruby_uart_t *self);
        void bareruby_uart_clear_rx_buffer(bareruby_uart_t *self);
        void bareruby_uart_clear_tx_buffer(bareruby_uart_t *self);

        void bareruby_i2c_init(bareruby_i2c_t *self, int32_t id, int32_t frequency);
        int32_t bareruby_i2c_write(
            bareruby_i2c_t *self, int32_t address, const char *bytes, int32_t length);
        bareruby_string_t *bareruby_i2c_read(
            bareruby_i2c_t *self, bareruby_arena_t *arena, int32_t address, int32_t length,
            const char *outputs, int32_t output_length);

        void bareruby_adc_init(bareruby_adc_t *self, int32_t pin);
        int32_t bareruby_adc_read(bareruby_adc_t *self);
        int32_t bareruby_adc_read_raw(bareruby_adc_t *self);

        void bareruby_machine_delay_us(int32_t microseconds);
        void bareruby_sleep(int32_t seconds);
        void bareruby_sleep_ms(int32_t milliseconds);
        void bareruby_asleep(int32_t seconds);
        void bareruby_asleep_ms(int32_t milliseconds);
        void bareruby_asleep_us(int32_t microseconds);

        #ifdef __cplusplus
        }
        #endif

        #endif
      CPP

      BINDING_HOST_SOURCE = <<~CPP
        #include "bareruby_binding.h"

        #include <stdarg.h>
        #include <stdio.h>
        #include <stdlib.h>
        #include <string.h>

        void bareruby_startup(void) {
            fprintf(stderr, "startup()\\n");
        }

        void bareruby_gpio_init(bareruby_gpio_t *self, int32_t pin, int32_t params) {
            self->pin = pin;
            self->params = params;
            fprintf(stderr, "gpio_init(pin=%d, params=%d)\\n", (int)pin, (int)params);
        }

        void bareruby_gpio_write(bareruby_gpio_t *self, int32_t value) {
            fprintf(stderr, "gpio_write(pin=%d, value=%d)\\n", (int)self->pin, (int)value);
        }

        int32_t bareruby_gpio_read(bareruby_gpio_t *self) {
            fprintf(stderr, "gpio_read(pin=%d) -> 0\\n", (int)self->pin);
            return 0;
        }

        bool bareruby_gpio_high(bareruby_gpio_t *self) {
            fprintf(stderr, "gpio_high(pin=%d) -> false\\n", (int)self->pin);
            return false;
        }

        bool bareruby_gpio_low(bareruby_gpio_t *self) {
            fprintf(stderr, "gpio_low(pin=%d) -> true\\n", (int)self->pin);
            return true;
        }

        void bareruby_pwm_init(bareruby_pwm_t *self, int32_t pin, int32_t frequency, int32_t duty) {
            self->pin = pin;
            self->slice = pin / 2;
            self->frequency = frequency;
            fprintf(stderr, "pwm_init(pin=%d, frequency=%d, duty=%d)\\n", (int)pin, (int)frequency, (int)duty);
        }

        void bareruby_pwm_frequency(bareruby_pwm_t *self, int32_t frequency) {
            self->frequency = frequency;
            fprintf(stderr, "pwm_frequency(pin=%d, frequency=%d)\\n", (int)self->pin, (int)frequency);
        }

        void bareruby_pwm_period_us(bareruby_pwm_t *self, int32_t period_us) {
            fprintf(stderr, "pwm_period_us(pin=%d, period_us=%d)\\n", (int)self->pin, (int)period_us);
        }

        void bareruby_pwm_duty(bareruby_pwm_t *self, int32_t duty) {
            fprintf(stderr, "pwm_duty(pin=%d, duty=%d)\\n", (int)self->pin, (int)duty);
        }

        void bareruby_pwm_pulse_width_us(bareruby_pwm_t *self, int32_t pulse_width_us) {
            fprintf(stderr, "pwm_pulse_width_us(pin=%d, pulse_width_us=%d)\\n", (int)self->pin, (int)pulse_width_us);
        }

        static void bareruby_trace_payload(const char *label, const bareruby_uart_t *self, const char *text) {
            fprintf(stderr, "%s(id=%d, text=\\"", label, (int)self->id);
            for (const char *cursor = text; *cursor != '\\0'; ++cursor) {
                if (*cursor == '\\n') {
                    fputs("\\\\n", stderr);
                } else {
                    fputc(*cursor, stderr);
                }
            }
            fputs("\\")\\n", stderr);
        }

        void bareruby_uart_init(bareruby_uart_t *self, int32_t id, int32_t baud, int32_t parity) {
            self->id = id;
            self->baud = baud;
            self->parity = parity;
            fprintf(stderr, "uart_init(id=%d, baud=%d, parity=%d)\\n", (int)id, (int)baud, (int)parity);
        }

        int32_t bareruby_uart_write(bareruby_uart_t *self, const char *value) {
            bareruby_trace_payload("uart_write", self, value);
            return (int32_t)strlen(value);
        }

        void bareruby_uart_puts(bareruby_uart_t *self, const char *value) {
            bareruby_trace_payload("uart_puts", self, value);
        }

        void bareruby_uart_printf(bareruby_uart_t *self, const char *format, ...) {
            char payload[256];
            va_list arguments;
            va_start(arguments, format);
            vsnprintf(payload, sizeof(payload), format, arguments);
            va_end(arguments);
            bareruby_trace_payload("uart_printf", self, payload);
        }

        int32_t bareruby_uart_bytes_available(bareruby_uart_t *self) {
            fprintf(stderr, "uart_bytes_available(id=%d) -> 0\\n", (int)self->id);
            return 0;
        }

        bool bareruby_uart_can_read_line(bareruby_uart_t *self) {
            fprintf(stderr, "uart_can_read_line(id=%d) -> false\\n", (int)self->id);
            return false;
        }

        void bareruby_uart_flush(bareruby_uart_t *self) {
            fprintf(stderr, "uart_flush(id=%d)\\n", (int)self->id);
        }

        void bareruby_uart_clear_rx_buffer(bareruby_uart_t *self) {
            fprintf(stderr, "uart_clear_rx_buffer(id=%d)\\n", (int)self->id);
        }

        void bareruby_uart_clear_tx_buffer(bareruby_uart_t *self) {
            fprintf(stderr, "uart_clear_tx_buffer(id=%d)\\n", (int)self->id);
        }

        void bareruby_adc_init(bareruby_adc_t *self, int32_t pin) {
            self->pin = pin;
            self->channel = pin - 26;
            fprintf(stderr, "adc_init(pin=%d, channel=%d)\\n", (int)pin, (int)self->channel);
        }

        int32_t bareruby_adc_read(bareruby_adc_t *self) {
            fprintf(stderr, "adc_read(pin=%d) -> 0\\n", (int)self->pin);
            return 0;
        }

        int32_t bareruby_adc_read_raw(bareruby_adc_t *self) {
            fprintf(stderr, "adc_read_raw(pin=%d) -> 0\\n", (int)self->pin);
            return 0;
        }

        void bareruby_machine_delay_us(int32_t microseconds) {
            fprintf(stderr, "machine_delay_us(microseconds=%d)\\n", (int)microseconds);
        }

        void bareruby_sleep(int32_t seconds) {
            fprintf(stderr, "sleep(seconds=%d)\\n", (int)seconds);
        }

        void bareruby_sleep_ms(int32_t milliseconds) {
            fprintf(stderr, "sleep_ms(milliseconds=%d)\\n", (int)milliseconds);
        }

        void bareruby_asleep(int32_t seconds) {
            fprintf(stderr, "asleep(seconds=%d)\\n", (int)seconds);
        }

        void bareruby_asleep_ms(int32_t milliseconds) {
            fprintf(stderr, "asleep_ms(milliseconds=%d)\\n", (int)milliseconds);
        }

        void bareruby_asleep_us(int32_t microseconds) {
            fprintf(stderr, "asleep_us(microseconds=%d)\\n", (int)microseconds);
        }
      CPP

      # stdin is the hosted UART wire. A pipe supplies the byte sequence for one run,
      # while the result still follows the peripheral trace on stderr.
      BINDING_UART_RECEIVE_HOST_SOURCE = <<~CPP
        #include "bareruby_binding.h"

        #include <stdio.h>

        static void bareruby_uart_trace_received(bareruby_string_t *value) {
            const char *bytes = bareruby_string_bytes(value);
            int32_t length = bareruby_string_length(value);
            fputc('"', stderr);
            for (int32_t index = 0; index < length; ++index) {
                unsigned char byte = (unsigned char)bytes[index];
                if (byte == '\\n') {
                    fputs("\\\\n", stderr);
                } else if (byte < 32 || byte > 126) {
                    fprintf(stderr, "\\\\x%02x", (unsigned int)byte);
                } else {
                    fputc((int)byte, stderr);
                }
            }
            fputs("\\"\\n", stderr);
        }

        bareruby_string_t *bareruby_uart_read(
            bareruby_uart_t *self, bareruby_arena_t *arena, int32_t length) {
            bareruby_string_t *result = bareruby_string_new(arena, "");
            for (int32_t index = 0; index < length; ++index) {
                bareruby_string_append_byte(result, fgetc(stdin));
            }
            fprintf(stderr, "uart_read(id=%d, length=%d) -> ", (int)self->id, (int)length);
            bareruby_uart_trace_received(result);
            return result;
        }

        bareruby_string_t *bareruby_uart_gets(bareruby_uart_t *self, bareruby_arena_t *arena) {
            bareruby_string_t *result = bareruby_string_new(arena, "");
            int byte;
            do {
                byte = fgetc(stdin);
                bareruby_string_append_byte(result, byte);
            } while (byte != '\\n');
            fprintf(stderr, "uart_gets(id=%d) -> ", (int)self->id);
            bareruby_uart_trace_received(result);
            return result;
        }
      CPP

      BINDING_I2C_HOST_SOURCE = <<~CPP
        #include "bareruby_binding.h"

        #include <stdio.h>

        static void bareruby_i2c_trace_bytes(const char *bytes, int32_t length) {
            fputc('"', stderr);
            for (int32_t index = 0; index < length; ++index) {
                unsigned char byte = (unsigned char)bytes[index];
                if (byte == '\\n') {
                    fputs("\\\\n", stderr);
                } else if (byte < 32 || byte > 126) {
                    fprintf(stderr, "\\\\x%02x", (unsigned int)byte);
                } else {
                    fputc((int)byte, stderr);
                }
            }
            fputc('"', stderr);
        }

        void bareruby_i2c_init(bareruby_i2c_t *self, int32_t id, int32_t frequency) {
            self->id = id;
            self->frequency = frequency;
            fprintf(stderr, "i2c_init(id=%d, frequency=%d)\\n", (int)id, (int)frequency);
        }

        int32_t bareruby_i2c_write(
            bareruby_i2c_t *self, int32_t address, const char *bytes, int32_t length) {
            fprintf(stderr, "i2c_write(id=%d, address=0x%02x, bytes=",
                    (int)self->id, (unsigned int)address);
            bareruby_i2c_trace_bytes(bytes, length);
            fprintf(stderr, ") -> %d\\n", (int)length);
            return length;
        }
      CPP

      BINDING_I2C_READ_HOST_SOURCE = <<~CPP
        #include "bareruby_binding.h"

        #include <stdio.h>

        static void bareruby_i2c_trace_read_bytes(const char *bytes, int32_t length) {
            fputc('"', stderr);
            for (int32_t index = 0; index < length; ++index) {
                unsigned char byte = (unsigned char)bytes[index];
                if (byte == '\\n') {
                    fputs("\\\\n", stderr);
                } else if (byte < 32 || byte > 126) {
                    fprintf(stderr, "\\\\x%02x", (unsigned int)byte);
                } else {
                    fputc((int)byte, stderr);
                }
            }
            fputc('"', stderr);
        }

        bareruby_string_t *bareruby_i2c_read(
            bareruby_i2c_t *self, bareruby_arena_t *arena, int32_t address, int32_t length,
            const char *outputs, int32_t output_length) {
            bareruby_string_t *result = bareruby_string_new(arena, "");
            for (int32_t index = 0; index < length; ++index) {
                bareruby_string_append_byte(result, fgetc(stdin));
            }
            fprintf(stderr, "i2c_read(id=%d, address=0x%02x, length=%d, outputs=",
                    (int)self->id, (unsigned int)address, (int)length);
            bareruby_i2c_trace_read_bytes(outputs, output_length);
            fputs(") -> ", stderr);
            bareruby_i2c_trace_read_bytes(
                bareruby_string_bytes(result), bareruby_string_length(result));
            fputc('\\n', stderr);
            return result;
        }
      CPP

      BINDING_RP2040_SOURCE = <<~CPP
        #include "bareruby_binding.h"

        #include <stdarg.h>
        #include <stdio.h>
        #include <string.h>

        #include "hardware/adc.h"
        #include "hardware/clocks.h"
        #include "hardware/gpio.h"
        #include "hardware/pwm.h"
        #include "hardware/uart.h"
        #include "pico/stdlib.h"

        void bareruby_startup(void) {
            stdio_init_all();
        }

        void bareruby_gpio_init(bareruby_gpio_t *self, int32_t pin, int32_t params) {
            self->pin = pin;
            self->params = params;
            gpio_init((uint)pin);
            gpio_set_dir((uint)pin, (params & 2) ? GPIO_OUT : GPIO_IN);
            if (params & 4) {
                gpio_set_input_enabled((uint)pin, false);
            }
            if (params & 8) {
                gpio_pull_up((uint)pin);
            } else if (params & 16) {
                gpio_pull_down((uint)pin);
            } else {
                gpio_disable_pulls((uint)pin);
            }
        }

        void bareruby_gpio_write(bareruby_gpio_t *self, int32_t value) {
            gpio_put((uint)self->pin, value != 0);
        }

        int32_t bareruby_gpio_read(bareruby_gpio_t *self) {
            return gpio_get((uint)self->pin) ? 1 : 0;
        }

        bool bareruby_gpio_high(bareruby_gpio_t *self) {
            return gpio_get((uint)self->pin);
        }

        bool bareruby_gpio_low(bareruby_gpio_t *self) {
            return !gpio_get((uint)self->pin);
        }

        void bareruby_pwm_init(bareruby_pwm_t *self, int32_t pin, int32_t frequency, int32_t duty) {
            self->pin = pin;
            self->slice = (int32_t)pwm_gpio_to_slice_num((uint)pin);
            gpio_set_function((uint)pin, GPIO_FUNC_PWM);
            bareruby_pwm_frequency(self, frequency);
            bareruby_pwm_duty(self, duty);
        }

        void bareruby_pwm_frequency(bareruby_pwm_t *self, int32_t frequency) {
            self->frequency = frequency;
            if (frequency <= 0) {
                pwm_set_enabled((uint)self->slice, false);
                return;
            }
            uint32_t divider = (clock_get_hz(clk_sys) / 1000000u);
            pwm_set_clkdiv((uint)self->slice, (float)divider);
            pwm_set_wrap((uint)self->slice, (uint16_t)((1000000u / (uint32_t)frequency) - 1u));
            pwm_set_enabled((uint)self->slice, true);
        }

        void bareruby_pwm_period_us(bareruby_pwm_t *self, int32_t period_us) {
            bareruby_pwm_frequency(self, period_us > 0 ? (int32_t)(1000000 / period_us) : 0);
        }

        void bareruby_pwm_duty(bareruby_pwm_t *self, int32_t duty) {
            uint16_t top = (uint16_t)pwm_hw->slice[self->slice].top;
            pwm_set_gpio_level((uint)self->pin, (uint16_t)((uint32_t)top * (uint32_t)duty / 100u));
        }

        void bareruby_pwm_pulse_width_us(bareruby_pwm_t *self, int32_t pulse_width_us) {
            pwm_set_gpio_level((uint)self->pin, (uint16_t)pulse_width_us);
        }

        void bareruby_uart_init(bareruby_uart_t *self, int32_t id, int32_t baud, int32_t parity) {
            self->id = id;
            self->baud = baud;
            self->parity = parity;
            uart_inst_t *port = (id == 0) ? uart0 : uart1;
            uart_init(port, (uint)baud);
            gpio_set_function((id == 0) ? 0u : 4u, GPIO_FUNC_UART);
            gpio_set_function((id == 0) ? 1u : 5u, GPIO_FUNC_UART);
        }

        static uart_inst_t *bareruby_uart_port(const bareruby_uart_t *self) {
            return (self->id == 0) ? uart0 : uart1;
        }

        int32_t bareruby_uart_write(bareruby_uart_t *self, const char *value) {
            size_t length = strlen(value);
            uart_write_blocking(bareruby_uart_port(self), (const uint8_t *)value, length);
            return (int32_t)length;
        }

        void bareruby_uart_puts(bareruby_uart_t *self, const char *value) {
            uart_puts(bareruby_uart_port(self), value);
            uart_putc(bareruby_uart_port(self), '\\n');
        }

        void bareruby_uart_printf(bareruby_uart_t *self, const char *format, ...) {
            char payload[256];
            va_list arguments;
            va_start(arguments, format);
            vsnprintf(payload, sizeof(payload), format, arguments);
            va_end(arguments);
            uart_puts(bareruby_uart_port(self), payload);
        }

        int32_t bareruby_uart_bytes_available(bareruby_uart_t *self) {
            return uart_is_readable(bareruby_uart_port(self)) ? 1 : 0;
        }

        bool bareruby_uart_can_read_line(bareruby_uart_t *self) {
            return uart_is_readable(bareruby_uart_port(self));
        }

        void bareruby_uart_flush(bareruby_uart_t *self) {
            uart_tx_wait_blocking(bareruby_uart_port(self));
        }

        void bareruby_uart_clear_rx_buffer(bareruby_uart_t *self) {
            while (uart_is_readable(bareruby_uart_port(self))) {
                (void)uart_getc(bareruby_uart_port(self));
            }
        }

        void bareruby_uart_clear_tx_buffer(bareruby_uart_t *self) {
            uart_tx_wait_blocking(bareruby_uart_port(self));
        }

        void bareruby_adc_init(bareruby_adc_t *self, int32_t pin) {
            self->pin = pin;
            self->channel = pin - 26;
            adc_init();
            adc_gpio_init((uint)pin);
        }

        int32_t bareruby_adc_read_raw(bareruby_adc_t *self) {
            adc_select_input((uint)self->channel);
            return (int32_t)adc_read();
        }

        int32_t bareruby_adc_read(bareruby_adc_t *self) {
            int64_t raw = (int64_t)bareruby_adc_read_raw(self);
            return (int32_t)((raw * 3300 * 65536) / (4095 * 1000));
        }

        void bareruby_machine_delay_us(int32_t microseconds) {
            sleep_us((uint64_t)microseconds);
        }

        void bareruby_sleep(int32_t seconds) {
            sleep_ms((uint32_t)seconds * 1000u);
        }

        void bareruby_sleep_ms(int32_t milliseconds) {
            sleep_ms((uint32_t)milliseconds);
        }

        // One mark serves all three units, and it counts microseconds since boot in 64
        // bits: 32 would wrap after 71 minutes, which the seconds form is meant to
        // outlast. Zero is boot time, so the first call needs no flag of its own. A late
        // turn does not try to catch up — the mark moves to the actual return and the
        // missed time is gone, which keeps one slow turn from firing the next ones back
        // to back.
        static uint64_t bareruby_asleep_mark = 0;

        static void bareruby_asleep_until(uint64_t interval) {
            uint64_t deadline = bareruby_asleep_mark + interval;
            if (time_us_64() < deadline) {
                sleep_until(from_us_since_boot(deadline));
            }
            bareruby_asleep_mark = time_us_64();
        }

        void bareruby_asleep(int32_t seconds) {
            bareruby_asleep_until((uint64_t)seconds * 1000000u);
        }

        void bareruby_asleep_ms(int32_t milliseconds) {
            bareruby_asleep_until((uint64_t)milliseconds * 1000u);
        }

        void bareruby_asleep_us(int32_t microseconds) {
            bareruby_asleep_until((uint64_t)microseconds);
        }
      CPP

      BINDING_UART_RECEIVE_RP2040_SOURCE = <<~CPP
        #include "bareruby_binding.h"

        #include "hardware/uart.h"

        static uart_inst_t *bareruby_uart_receive_port(const bareruby_uart_t *self) {
            return (self->id == 0) ? uart0 : uart1;
        }

        bareruby_string_t *bareruby_uart_read(
            bareruby_uart_t *self, bareruby_arena_t *arena, int32_t length) {
            bareruby_string_t *result = bareruby_string_new(arena, "");
            for (int32_t index = 0; index < length; ++index) {
                bareruby_string_append_byte(result, uart_getc(bareruby_uart_receive_port(self)));
            }
            return result;
        }

        bareruby_string_t *bareruby_uart_gets(bareruby_uart_t *self, bareruby_arena_t *arena) {
            bareruby_string_t *result = bareruby_string_new(arena, "");
            int byte;
            do {
                byte = uart_getc(bareruby_uart_receive_port(self));
                bareruby_string_append_byte(result, byte);
            } while (byte != '\\n');
            return result;
        }
      CPP

      BINDING_I2C_RP2040_SOURCE = <<~CPP
        #include "bareruby_binding.h"

        #include "hardware/gpio.h"
        #include "hardware/i2c.h"

        static i2c_inst_t *bareruby_i2c_port(const bareruby_i2c_t *self) {
            return (self->id == 0) ? i2c0 : i2c1;
        }

        void bareruby_i2c_init(bareruby_i2c_t *self, int32_t id, int32_t frequency) {
            self->id = id;
            self->frequency = frequency;
            i2c_init(bareruby_i2c_port(self), (uint)frequency);
            uint sda_pin = (id == 0) ? 4u : 6u;
            uint scl_pin = (id == 0) ? 5u : 7u;
            gpio_set_function(sda_pin, GPIO_FUNC_I2C);
            gpio_set_function(scl_pin, GPIO_FUNC_I2C);
            gpio_pull_up(sda_pin);
            gpio_pull_up(scl_pin);
        }

        int32_t bareruby_i2c_write(
            bareruby_i2c_t *self, int32_t address, const char *bytes, int32_t length) {
            return i2c_write_blocking(
                bareruby_i2c_port(self), (uint8_t)address, (const uint8_t *)bytes,
                (size_t)length, false);
        }
      CPP

      BINDING_I2C_READ_RP2040_SOURCE = <<~CPP
        #include "bareruby_binding.h"

        #include "hardware/i2c.h"

        static i2c_inst_t *bareruby_i2c_read_port(const bareruby_i2c_t *self) {
            return (self->id == 0) ? i2c0 : i2c1;
        }

        bareruby_string_t *bareruby_i2c_read(
            bareruby_i2c_t *self, bareruby_arena_t *arena, int32_t address, int32_t length,
            const char *outputs, int32_t output_length) {
            i2c_inst_t *port = bareruby_i2c_read_port(self);
            if (0 < output_length) {
                i2c_write_blocking(
                    port, (uint8_t)address, (const uint8_t *)outputs,
                    (size_t)output_length, true);
            }

            uint8_t bytes[length];
            int32_t received = i2c_read_blocking(
                port, (uint8_t)address, bytes, (size_t)length, false);
            bareruby_string_t *result = bareruby_string_new(arena, "");
            for (int32_t index = 0; index < received; ++index) {
                bareruby_string_append_byte(result, bytes[index]);
            }
            return result;
        }
      CPP

      attr_reader :result, :stdout_notice

      def initialize(low_ir, debug:, exceptions: true)
        @lir = low_ir
        @debug = debug
        @exceptions = exceptions
        @stdout_notice = false
      end

      def run
        rp2040_program = program_source(:rp2040)
        @result = {
          "bareruby_runtime.h" => RUNTIME_HEADER,
          "bareruby_runtime_fixed.cpp" => RUNTIME_FIXED_SOURCE,
          "bareruby_runtime_arena.cpp" => RUNTIME_ARENA_SOURCE,
          "bareruby_runtime_string.cpp" => RUNTIME_STRING_SOURCE,
          "bareruby_runtime_throw.cpp" => RUNTIME_THROW_SOURCE,
          "bareruby_runtime_stdio.cpp" => RUNTIME_STDIO_SOURCE,
          "bareruby_binding.h" => BINDING_HEADER,
          "bareruby_binding_host.cpp" => BINDING_HOST_SOURCE,
          "bareruby_binding_rp2040.cpp" => BINDING_RP2040_SOURCE,
          "bareruby_binding_uart_receive_host.cpp" => BINDING_UART_RECEIVE_HOST_SOURCE,
          "bareruby_binding_uart_receive_rp2040.cpp" => BINDING_UART_RECEIVE_RP2040_SOURCE,
          "bareruby_binding_i2c_host.cpp" => BINDING_I2C_HOST_SOURCE,
          "bareruby_binding_i2c_read_host.cpp" => BINDING_I2C_READ_HOST_SOURCE,
          "bareruby_binding_i2c_rp2040.cpp" => BINDING_I2C_RP2040_SOURCE,
          "bareruby_binding_i2c_read_rp2040.cpp" => BINDING_I2C_READ_RP2040_SOURCE,
          "hosted/main.cpp" => program_source(:hosted),
          "hosted/manifest.txt" => hosted_manifest,
          "rp2040/main.cpp" => rp2040_program,
          "rp2040/manifest.txt" => rp2040_manifest,
          "rp2040/CMakeLists.txt" => cmake_lists
        }

        self
      end

      def hosted_sources
        sources = ["main.cpp", "../bareruby_binding_host.cpp", "../bareruby_runtime_fixed.cpp",
                   "../bareruby_runtime_stdio.cpp"]
        sources << "../bareruby_binding_uart_receive_host.cpp" if receives_uart?
        sources << "../bareruby_binding_i2c_host.cpp" if uses_i2c?
        sources << "../bareruby_binding_i2c_read_host.cpp" if reads_i2c?
        sources << "../bareruby_runtime_arena.cpp" if allocates?
        sources << "../bareruby_runtime_string.cpp" if builds_strings?
        sources << "../bareruby_runtime_throw.cpp" if throws?
        sources
      end

      def hosted_manifest
        <<~MANIFEST
          target = hosted
          toolchain = g++
          language_standard = gnu++20
          compile_options = -std=gnu++20 -fno-rtti
          include_directories = ..
          sources = #{hosted_sources.join(' ')}
          link_libraries =
          stdout_channel = printf
          exceptions = enabled
          artifact = bareruby_program
          build_command = g++ -std=gnu++20 -fno-rtti -I.. -o bareruby_program #{hosted_sources.join(' ')}
        MANIFEST
      end

      # Only a program that raises needs the throw translation unit linked.
      def throws?
        @lir.functions.any? { |function| calls_throw?(@lir.children_of(function)[3]) }
      end

      def calls_throw?(value)
        return value.any? { |element| calls_throw?(element) } if value.is_a?(Array)
        return false unless value.is_a?(Hash)
        return true if value[:type] == :call && value[:children][0] == :bareruby_throw

        calls_throw?(value[:children])
      end

      # A program with no arena never links the allocator, so a program that keeps to the
      # first two layers of the memory model pays nothing for the third.
      def allocates?
        @lir.functions.any? { |function| declares_arena?(@lir.children_of(function)[3]) }
      end

      def declares_arena?(value)
        return value.any? { |element| declares_arena?(element) } if value.is_a?(Array)
        return false unless value.is_a?(Hash)
        return true if value[:type] == :declare_arena_storage

        declares_arena?(value[:children])
      end

      # A program that keeps to static and fixed-capacity strings never links the string
      # runtime either, which costs stdio's vsnprintf on top of the region it allocates from.
      def builds_strings?
        @lir.functions.any? { |function| calls_string?(@lir.children_of(function)[3]) }
      end

      def calls_string?(value)
        return value.any? { |element| calls_string?(element) } if value.is_a?(Array)
        return false unless value.is_a?(Hash)
        if value[:type] == :call
          function = value[:children][0]
          return true if function.to_s.start_with?("bareruby_string_") ||
                         %i[bareruby_uart_read bareruby_uart_gets bareruby_i2c_read].include?(function)
        end

        calls_string?(value[:children])
      end

      def receives_uart?
        @lir.functions.any? { |function| calls_uart_receive?(@lir.children_of(function)[3]) }
      end

      def calls_uart_receive?(value)
        return value.any? { |element| calls_uart_receive?(element) } if value.is_a?(Array)
        return false unless value.is_a?(Hash)
        return true if value[:type] == :call &&
                       %i[bareruby_uart_read bareruby_uart_gets].include?(value[:children][0])

        calls_uart_receive?(value[:children])
      end

      def uses_i2c?
        @lir.functions.any? { |function| calls_i2c?(@lir.children_of(function)[3]) }
      end

      def calls_i2c?(value)
        return value.any? { |element| calls_i2c?(element) } if value.is_a?(Array)
        return false unless value.is_a?(Hash)
        return true if value[:type] == :call &&
                       value[:children][0].to_s.start_with?("bareruby_i2c_")

        calls_i2c?(value[:children])
      end

      def reads_i2c?
        @lir.functions.any? { |function| calls_i2c_read?(@lir.children_of(function)[3]) }
      end

      def calls_i2c_read?(value)
        return value.any? { |element| calls_i2c_read?(element) } if value.is_a?(Array)
        return false unless value.is_a?(Hash)
        return true if value[:type] == :call && value[:children][0] == :bareruby_i2c_read

        calls_i2c_read?(value[:children])
      end

      def rp2040_sources
        sources = ["main.cpp", "../bareruby_binding_rp2040.cpp", "../bareruby_runtime_fixed.cpp",
                   "../bareruby_runtime_stdio.cpp"]
        sources << "../bareruby_binding_uart_receive_rp2040.cpp" if receives_uart?
        sources << "../bareruby_binding_i2c_rp2040.cpp" if uses_i2c?
        sources << "../bareruby_binding_i2c_read_rp2040.cpp" if reads_i2c?
        sources << "../bareruby_runtime_arena.cpp" if allocates?
        sources << "../bareruby_runtime_string.cpp" if builds_strings?
        sources << "../bareruby_runtime_throw.cpp" if throws?
        sources
      end

      def rp2040_manifest
        <<~MANIFEST
          target = freestanding-rp2040
          toolchain = arm-none-eabi-g++
          language_standard = gnu++20
          compile_options = -std=gnu++20 -fno-rtti
          include_directories = ..
          sources = #{rp2040_sources.join(' ')}
          link_libraries = pico_stdlib hardware_adc hardware_gpio hardware_pwm hardware_uart hardware_i2c hardware_clocks
          stdout_channel = #{@debug ? 'usb' : 'none'}
          debug = #{@debug ? 'enabled' : 'disabled'}
          exceptions = #{@exceptions ? 'enabled' : 'disabled'}
          artifact = bareruby_program.uf2
          build_command = cmake -B build -S . && cmake --build build
        MANIFEST
      end

      def cmake_lists
        <<~CMAKE
          cmake_minimum_required(VERSION 3.13)

          include($ENV{PICO_SDK_PATH}/external/pico_sdk_import.cmake)

          # pico-sdk leaves C++ exceptions off unless asked, so whether the unwinder and
          # its tables are linked is a decision the first stage records here.
          set(PICO_CXX_ENABLE_EXCEPTIONS #{@exceptions ? 1 : 0})

          project(bareruby_program C CXX ASM)
          set(CMAKE_C_STANDARD 11)
          set(CMAKE_CXX_STANDARD 20)

          pico_sdk_init()

          add_executable(bareruby_program
          #{rp2040_sources.map { |source| "    #{source}" }.join("\n")}
          )

          target_include_directories(bareruby_program PRIVATE ..)
          target_compile_options(bareruby_program PRIVATE $<$<COMPILE_LANGUAGE:CXX>:-fno-rtti#{@exceptions ? '' : ' -fno-exceptions'}>)
          target_link_libraries(bareruby_program pico_stdlib hardware_adc hardware_gpio hardware_pwm hardware_uart hardware_i2c hardware_clocks)
          #{cmake_stdio_text}
          pico_add_extra_outputs(bareruby_program)
        CMAKE
      end

      def cmake_stdio_text
        return "\npico_enable_stdio_usb(bareruby_program 0)\npico_enable_stdio_uart(bareruby_program 0)\n" unless @debug

        <<~CMAKE

          pico_enable_stdio_usb(bareruby_program 1)
          pico_enable_stdio_uart(bareruby_program 0)

          # Keep the USB device enumerated so the board can be reset into BOOTSEL from
          # the host instead of by replugging it with the button held.
          target_compile_definitions(bareruby_program PRIVATE
              PICO_STDIO_USB_ENABLE_RESET_VIA_BAUD_RATE=1
              PICO_STDIO_USB_RESET_MAGIC_BAUD_RATE=1200
              PICO_STDIO_USB_ENABLE_RESET_VIA_VENDOR_INTERFACE=1
          )
        CMAKE
      end

      def program_source(target)
        @target = target
        sections = [include_text(target)]
        sections.concat(@lir.structs.map { |struct| struct_text(struct) })
        sections << "#{@lir.functions.map { |function| "#{signature_text(function)};" }.join("\n")}\n"
        sections.concat(@lir.functions.map { |function| function_text(function) })
        sections << entry_text(target)
        sections.join("\n")
      end

      # The runtime header is always included: Fixed arithmetic is declared there and is
      # needed whether or not the build has a stdout channel.
      def include_text(_target)
        lines = ["#include <stdbool.h>", "#include <stdint.h>", "",
                 "#include \"bareruby_binding.h\"", "#include \"bareruby_runtime.h\""]
        "#{lines.join("\n")}\n"
      end

      def stdout_enabled?(target) = target == :hosted || @debug

      def entry_text(target)
        return "int main(void) {\n    bareruby_main();\n    return 0;\n}\n" if target == :hosted

        "int main(void) {\n    bareruby_startup();\n    bareruby_main();\n    for (;;) {\n" \
          "        bareruby_sleep_ms(1000);\n    }\n}\n"
      end

      def struct_text(struct)
        name, fields = @lir.children_of(struct)
        lines = ["struct #{name} {"]
        lines += fields.map { |field| "    #{declaration_text(field[:type], field[:name])};" }
        lines << "};\n"
        lines.join("\n")
      end

      def signature_text(function)
        name, parameters, return_type, = @lir.children_of(function)
        parameter_text =
          if parameters.empty?
            "void"
          else
            parameters.map { |parameter| declaration_text(parameter[:type], parameter[:name]) }.join(", ")
          end
        "static #{type_text(return_type)} #{name}(#{parameter_text})"
      end

      def function_text(function)
        body = @lir.children_of(function)[3]
        lines = ["#{signature_text(function)} {"]
        lines += body.flat_map { |statement| statement_lines(statement, "    ") }
        lines << "}\n"
        lines.join("\n")
      end

      def statement_lines(statement, indent)
        case @lir.node_type(statement)
        when :declare, :assign, :return
          ["#{indent}#{simple_statement_text(statement)};"]
        when :declare_buffer
          name, capacity = @lir.children_of(statement)
          ["#{indent}char #{name}[#{capacity}];"]
        when :declare_arena_storage
          name, capacity = @lir.children_of(statement)
          ["#{indent}static unsigned char #{name}[#{capacity}];"]
        when :scope
          ["#{indent}{"] +
            @lir.children_of(statement)[0].flat_map { |child| statement_lines(child, "#{indent}    ") } +
            ["#{indent}}"]
        when :expression
          expression_statement_lines(statement, indent)
        when :for
          init, condition, step, body = @lir.children_of(statement)
          header = "#{indent}for (#{simple_statement_text(init)}; " \
                   "#{expression_text(condition)}; #{simple_statement_text(step)}) {"
          [header] + body.flat_map { |child| statement_lines(child, "#{indent}    ") } + ["#{indent}}"]
        when :while
          condition, body = @lir.children_of(statement)
          ["#{indent}while (#{expression_text(condition)}) {"] +
            body.flat_map { |child| statement_lines(child, "#{indent}    ") } + ["#{indent}}"]
        when :if
          condition, then_body, else_body = @lir.children_of(statement)
          lines = ["#{indent}if (#{expression_text(condition)}) {"] +
                  then_body.flat_map { |child| statement_lines(child, "#{indent}    ") }
          if else_body
            lines << "#{indent}} else {"
            lines += else_body.flat_map { |child| statement_lines(child, "#{indent}    ") }
          end
          lines + ["#{indent}}"]
        when :try
          body, rescue_body = @lir.children_of(statement)
          ["#{indent}try {"] + body.flat_map { |child| statement_lines(child, "#{indent}    ") } +
            ["#{indent}} catch (...) {"] +
            rescue_body.flat_map { |child| statement_lines(child, "#{indent}    ") } + ["#{indent}}"]
        when :break
          ["#{indent}break;"]
        when :next
          ["#{indent}continue;"]
        end
      end

      def expression_statement_lines(statement, indent)
        value = @lir.children_of(statement)[0]
        if !stdout_enabled?(@target) && @lir.node_type(value) == :call &&
           PUTS_FUNCTIONS.include?(@lir.children_of(value)[0])
          @stdout_notice = true
          return []
        end

        ["#{indent}#{expression_text(value)};"]
      end

      def simple_statement_text(statement)
        case @lir.node_type(statement)
        when :declare
          name, type, value = @lir.children_of(statement)
          text = declaration_text(type, name)
          value ? "#{text} = #{expression_text(value)}" : text
        when :assign
          place, value = @lir.children_of(statement)
          "#{expression_text(place)} = #{expression_text(value)}"
        when :expression
          expression_text(@lir.children_of(statement)[0])
        when :return
          value = @lir.children_of(statement)[0]
          value ? "return #{expression_text(value)}" : "return"
        end
      end

      def expression_text(node)
        case @lir.node_type(node)
        when :const_int
          value, type = @lir.children_of(node)
          type == :int64 ? "#{value}LL" : value.to_s
        when :const_bool
          @lir.children_of(node)[0].to_s
        when :const_string
          string_literal(@lir.children_of(node)[0])
        when :local
          @lir.children_of(node)[0].to_s
        when :self_pointer
          "self"
        when :field_access
          base, name, = @lir.children_of(node)
          separator = pointer_type?(@lir.value_type(base)) ? "->" : "."
          "#{expression_text(base)}#{separator}#{name}"
        when :address_of
          "&#{expression_text(@lir.children_of(node)[0])}"
        when :index
          base, index, = @lir.children_of(node)
          "#{expression_text(base)}[#{expression_text(index)}]"
        when :binary
          operator, left, right, = @lir.children_of(node)
          "(#{expression_text(left)} #{operator} #{expression_text(right)})"
        when :unary
          operator, operand, = @lir.children_of(node)
          "(#{operator}#{expression_text(operand)})"
        when :call
          name, arguments, = @lir.children_of(node)
          "#{name}(#{arguments.map { |argument| expression_text(argument) }.join(', ')})"
        when :cast
          value, type = @lir.children_of(node)
          "(#{type_text(type)})#{expression_text(value)}"
        when :size_of
          "(int32_t)sizeof(#{type_text(@lir.children_of(node)[0])})"
        when :brace_init
          values, = @lir.children_of(node)
          "{ #{values.map { |value| expression_text(value) }.join(', ')} }"
        end
      end

      def pointer_type?(type) = type.is_a?(Hash) && type[:kind] == :pointer

      def declaration_text(type, name)
        return "#{type_text(type[:target])} *#{name}" if pointer_type?(type)
        return "#{type_text(type[:element])} #{name}[#{type[:capacity]}]" if c_array_type?(type)

        "#{type_text(type)} #{name}"
      end

      def c_array_type?(type) = type.is_a?(Hash) && type[:kind] == :c_array

      def string_literal(value)
        bytes = value.b.bytes.map do |byte|
          case byte
          when 34 then '\\"'
          when 92 then "\\\\"
          when 10 then "\\n"
          when 9 then "\\t"
          when 13 then "\\r"
          when 32..126 then byte.chr
          else format("\\%03o", byte)
          end
        end
        "\"#{bytes.join}\""
      end

      def type_text(type)
        case type
        when :int32 then "int32_t"
        when :int64 then "int64_t"
        when :uint8 then "unsigned char"
        when :bool then "bool"
        when :fixed then "int32_t"
        when :string_ptr then "const char *"
        when :void then "void"
        when Hash
          type[:kind] == :pointer ? "#{type_text(type[:target])} *" : type[:name].to_s
        end
      end
    end
  end
end
