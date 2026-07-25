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
        void bareruby_panic(const char *message);
        void bareruby_throw(const char *message);
        void bareruby_format(char *buffer, int32_t capacity, const char *format, ...);

        #ifdef __cplusplus
        }
        #endif

        #endif
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
        int32_t bareruby_uart_bytes_available(bareruby_uart_t *self);
        bool bareruby_uart_can_read_line(bareruby_uart_t *self);
        void bareruby_uart_flush(bareruby_uart_t *self);
        void bareruby_uart_clear_rx_buffer(bareruby_uart_t *self);
        void bareruby_uart_clear_tx_buffer(bareruby_uart_t *self);

        void bareruby_adc_init(bareruby_adc_t *self, int32_t pin);
        int32_t bareruby_adc_read(bareruby_adc_t *self);
        int32_t bareruby_adc_read_raw(bareruby_adc_t *self);

        void bareruby_machine_delay_us(int32_t microseconds);
        void bareruby_sleep(int32_t seconds);
        void bareruby_sleep_ms(int32_t milliseconds);

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
          "bareruby_runtime_throw.cpp" => RUNTIME_THROW_SOURCE,
          "bareruby_runtime_stdio.cpp" => RUNTIME_STDIO_SOURCE,
          "bareruby_binding.h" => BINDING_HEADER,
          "bareruby_binding_host.cpp" => BINDING_HOST_SOURCE,
          "bareruby_binding_rp2040.cpp" => BINDING_RP2040_SOURCE,
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

      def rp2040_sources
        sources = ["main.cpp", "../bareruby_binding_rp2040.cpp", "../bareruby_runtime_fixed.cpp",
                   "../bareruby_runtime_stdio.cpp"]
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
          link_libraries = pico_stdlib hardware_adc hardware_gpio hardware_pwm hardware_uart hardware_clocks
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
          target_link_libraries(bareruby_program pico_stdlib hardware_adc hardware_gpio hardware_pwm hardware_uart hardware_clocks)
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
        end
      end

      def pointer_type?(type) = type.is_a?(Hash) && type[:kind] == :pointer

      def declaration_text(type, name)
        return "#{type_text(type[:target])} *#{name}" if pointer_type?(type)
        return "#{type_text(type[:element])} #{name}[#{type[:capacity]}]" if c_array_type?(type)

        "#{type_text(type)} #{name}"
      end

      def c_array_type?(type) = type.is_a?(Hash) && type[:kind] == :c_array

      ESCAPES = { "\\" => "\\\\", '"' => '\\"', "\n" => "\\n", "\t" => "\\t", "\r" => "\\r" }.freeze

      def string_literal(value)
        "\"#{value.gsub(/[\\"\n\t\r]/) { |character| ESCAPES.fetch(character) }}\""
      end

      def type_text(type)
        case type
        when :int32 then "int32_t"
        when :int64 then "int64_t"
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
