# frozen_string_literal: true

module BareRubyProt
  module RuntimeSource
    HEADER = <<~CPP
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
    ARENA = <<~CPP
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
    STRING = <<~CPP
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
    FIXED = <<~CPP
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
    THROW = <<~CPP
      #include "bareruby_runtime.h"

      void bareruby_throw(const char *message) {
          throw message;
      }
    CPP

    STDIO = <<~CPP
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

    FILES = {
      "bareruby_runtime.h" => HEADER,
      "bareruby_runtime_fixed.cpp" => FIXED,
      "bareruby_runtime_arena.cpp" => ARENA,
      "bareruby_runtime_string.cpp" => STRING,
      "bareruby_runtime_throw.cpp" => THROW,
      "bareruby_runtime_stdio.cpp" => STDIO
    }.freeze
  end
end
