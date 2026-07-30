# frozen_string_literal: true

require_relative "../../standard_library"
require_relative "native_declaration"

module BareRubyProt
  module HostBindingSource
    PERIPHERAL_PREAMBLE = <<~CPP
      #include "bareruby_binding.h"

      #include <stdarg.h>
      #include <stdio.h>
      #include <stdlib.h>
      #include <string.h>

      void bareruby_startup(void) {
          fprintf(stderr, "startup()\\n");
      }
    CPP

    PERIPHERAL_REMAINDER = <<~CPP
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
    UART_RECEIVE = <<~CPP
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

    I2C = <<~CPP
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

    I2C_READ = <<~CPP
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

    PERIPHERAL_FILE = "bareruby_binding_host.cpp"
    UART_RECEIVE_FILE = "bareruby_binding_uart_receive_host.cpp"
    I2C_FILE = "bareruby_binding_i2c_host.cpp"
    I2C_READ_FILE = "bareruby_binding_i2c_read_host.cpp"

    VARIANT = :hosted

    # The peripherals whose implementations this file carries, in the order it carries
    # them. The C++ is the declaring class's, and the order is this file's.
    NATIVE_CLASSES = %i[GPIO].freeze

    # The preamble names what the whole file needs and starts the program off; each class
    # then contributes what it needs above its own methods and the methods themselves.
    def self.peripheral
      parts = NATIVE_CLASSES.flat_map do |name|
        NativeDeclaration.new(StandardLibrary[name]).definitions(variant_of(name))
      end
      ([PERIPHERAL_PREAMBLE] + parts + [PERIPHERAL_REMAINDER]).join("\n")
    end

    def self.variant_of(name) = StandardLibrary[name].variant(VARIANT)

    def self.files
      {
        PERIPHERAL_FILE => peripheral,
        UART_RECEIVE_FILE => UART_RECEIVE,
        I2C_FILE => I2C,
        I2C_READ_FILE => I2C_READ
      }
    end

    ALWAYS = [PERIPHERAL_FILE].freeze
  end
end
