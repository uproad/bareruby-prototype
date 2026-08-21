# frozen_string_literal: true

module BareRubyProt
  module HostBinding
    # GPIO in its own translation unit. **A peripheral that can be uninstalled cannot
    # share a file with one that cannot** — the declarations go with the gem, and an
    # implementation left behind would have nothing to implement against.
    PWM = <<~CPP
      #include "bareruby_binding.h"
      #include <stdarg.h>
      #include <stdio.h>
      #include <stdlib.h>
      #include <string.h>

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
    CPP

    ADC = <<~CPP
      #include "bareruby_binding.h"
      #include <stdarg.h>
      #include <stdio.h>
      #include <stdlib.h>
      #include <string.h>

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
    CPP

    UART = <<~CPP
      #include "bareruby_binding.h"
      #include <stdarg.h>
      #include <stdio.h>
      #include <stdlib.h>
      #include <string.h>

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

      void bareruby_uart_init(
          bareruby_uart_t *self, int32_t id, int32_t baud,
          int32_t data_bits, int32_t stop_bits, int32_t parity) {
          self->id = id;
          self->baud = baud;
          self->data_bits = data_bits;
          self->stop_bits = stop_bits;
          self->parity = parity;
          fprintf(stderr, "uart_init(id=%d, baud=%d, data_bits=%d, stop_bits=%d, parity=%d)\\n",
                  (int)id, (int)baud, (int)data_bits, (int)stop_bits, (int)parity);
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

      /* Weak, so the uart_interrupt unit's ring-backed answer replaces this one the
         moment a program touches the buffered receive side. */
      __attribute__((weak)) int32_t bareruby_uart_bytes_available(bareruby_uart_t *self) {
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

      /* Nothing is held back here: a write reaches the descriptor before it returns, so
         the send side owes the wire nothing by the time this can be asked. */
      int32_t bareruby_uart_bytes_to_write(bareruby_uart_t *self) {
          fprintf(stderr, "uart_bytes_to_write(id=%d) -> 0\\n", (int)self->id);
          return 0;
      }

      void bareruby_uart_send_break(bareruby_uart_t *self, int32_t milliseconds) {
          fprintf(stderr, "uart_send_break(id=%d, milliseconds=%d)\\n",
                  (int)self->id, (int)milliseconds);
      }

      void bareruby_uart_clear_rx_buffer(bareruby_uart_t *self) {
          fprintf(stderr, "uart_clear_rx_buffer(id=%d)\\n", (int)self->id);
      }

      void bareruby_uart_clear_tx_buffer(bareruby_uart_t *self) {
          fprintf(stderr, "uart_clear_tx_buffer(id=%d)\\n", (int)self->id);
      }
    CPP

    GPIO = <<~CPP
      #include "bareruby_binding.h"
      #include <stdarg.h>
      #include <stdio.h>
      #include <stdlib.h>
      #include <string.h>

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

      void bareruby_gpio_on_interrupt(
          bareruby_gpio_t *self, int32_t events, bareruby_interrupt_handler_t handler) {
          fprintf(stderr, "gpio_on_interrupt(pin=%d, events=%d)\\n", (int)self->pin, (int)events);
          handler();
      }
    CPP

    PERIPHERAL = <<~CPP
      #include "bareruby_binding.h"

      #include <stdarg.h>
      #include <stdio.h>
      #include <stdlib.h>
      #include <string.h>
      #include <time.h>

      /* The uart_interrupt unit overrides this when a program says on_line; otherwise
         sleep drains nothing and pays one empty call. */
      extern "C" __attribute__((weak)) void bareruby_uart_interrupt_drain(void) {}

      void bareruby_startup(void) {
          fprintf(stderr, "startup()\\n");
      }

      /* A clock read is not an event, so it leaves no trace: a timeout loop would flood
         stderr with lines that say only that time passed. */
      int32_t bareruby_ticks_ms(void) {
          struct timespec now;
          clock_gettime(CLOCK_MONOTONIC, &now);
          return (int32_t)((int64_t)now.tv_sec * 1000 + now.tv_nsec / 1000000);
      }




      void bareruby_machine_delay_us(int32_t microseconds) {
          fprintf(stderr, "machine_delay_us(microseconds=%d)\\n", (int)microseconds);
      }

      /* No time passes here, so what a wait is worth watching for is whether it
         delivered: the flag it was given is in the trace beside the interval, and the
         drain either runs under it or does not. */
      static const char *bareruby_wait_interrupt(bool interrupt) {
          return interrupt ? "true" : "false";
      }

      static void bareruby_wait_deliver(bool interrupt) {
          if (interrupt) {
              bareruby_uart_interrupt_drain();
          }
      }

      void bareruby_sleep(int32_t seconds, bool interrupt) {
          fprintf(stderr, "sleep(seconds=%d, interrupt=%s)\\n", (int)seconds,
                  bareruby_wait_interrupt(interrupt));
          bareruby_wait_deliver(interrupt);
      }

      void bareruby_sleep_ms(int32_t milliseconds, bool interrupt) {
          fprintf(stderr, "sleep_ms(milliseconds=%d, interrupt=%s)\\n", (int)milliseconds,
                  bareruby_wait_interrupt(interrupt));
          bareruby_wait_deliver(interrupt);
      }

      void bareruby_asleep(int32_t seconds, bool interrupt) {
          fprintf(stderr, "asleep(seconds=%d, interrupt=%s)\\n", (int)seconds,
                  bareruby_wait_interrupt(interrupt));
          bareruby_wait_deliver(interrupt);
      }

      void bareruby_asleep_ms(int32_t milliseconds, bool interrupt) {
          fprintf(stderr, "asleep_ms(milliseconds=%d, interrupt=%s)\\n", (int)milliseconds,
                  bareruby_wait_interrupt(interrupt));
          bareruby_wait_deliver(interrupt);
      }

      void bareruby_asleep_us(int32_t microseconds, bool interrupt) {
          fprintf(stderr, "asleep_us(microseconds=%d, interrupt=%s)\\n", (int)microseconds,
                  bareruby_wait_interrupt(interrupt));
          bareruby_wait_deliver(interrupt);
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

    # The receive side an interrupt feeds, hosted: there is no wire to interrupt from, so
    # the first touch — a registration or a buffered read — puts stdin into non-blocking
    # mode, and the pump plays the ISR's part, reading whatever has arrived into the ring.
    # With a handler registered the drain assembles lines exactly as a board does, so
    # CRLF, the 255-byte cap and the overlong discard behave byte for byte the same;
    # without one the bytes stay in the ring for read_byte, peek and bytes_available.
    UART_INTERRUPT = <<~CPP
      #include "bareruby_binding.h"

      #include <fcntl.h>
      #include <stdio.h>
      #include <unistd.h>

      typedef struct {
          volatile uint8_t data[256];   /* the 256 bytes the receive side costs */
          volatile uint8_t head;        /* producer-owned */
          volatile uint8_t tail;        /* drain-owned */
          char line[256];               /* the view a handler is handed points here */
          int32_t line_length;
          bool discarding;              /* an overlong line, thrown away to the next LF */
          bareruby_uart_line_handler_t handler;
          bool attached;
      } bareruby_uart_interrupt_t;

      static bareruby_uart_interrupt_t bareruby_uart_interrupt;

      static void bareruby_uart_interrupt_push(uint8_t byte) {
          uint8_t next = (uint8_t)(bareruby_uart_interrupt.head + 1u);
          if (next == bareruby_uart_interrupt.tail) {
              return;   /* a full ring drops the byte */
          }
          bareruby_uart_interrupt.data[bareruby_uart_interrupt.head] = byte;
          bareruby_uart_interrupt.head = next;
      }

      static void bareruby_uart_interrupt_pump(void) {
          if (!bareruby_uart_interrupt.attached) {
              bareruby_uart_interrupt.attached = true;
              fcntl(STDIN_FILENO, F_SETFL, fcntl(STDIN_FILENO, F_GETFL) | O_NONBLOCK);
          }
          unsigned char chunk[64];
          for (;;) {
              ssize_t received = read(STDIN_FILENO, chunk, sizeof(chunk));
              if (received <= 0) {
                  break;
              }
              for (ssize_t index = 0; index < received; ++index) {
                  bareruby_uart_interrupt_push(chunk[index]);
              }
          }
      }

      static void bareruby_uart_interrupt_trace_line(const char *bytes, int32_t length) {
          fputs("uart_line(line=\\"", stderr);
          for (int32_t index = 0; index < length; ++index) {
              unsigned char byte = (unsigned char)bytes[index];
              if (byte < 32 || byte > 126) {
                  fprintf(stderr, "\\\\x%02x", (unsigned int)byte);
              } else {
                  fputc((int)byte, stderr);
              }
          }
          fputs("\\")\\n", stderr);
      }

      static void bareruby_uart_interrupt_line_byte(uint8_t byte) {
          if (byte == '\\n') {
              if (bareruby_uart_interrupt.discarding) {
                  bareruby_uart_interrupt.discarding = false;
                  bareruby_uart_interrupt.line_length = 0;
                  return;
              }
              int32_t length = bareruby_uart_interrupt.line_length;
              if (length > 0 && bareruby_uart_interrupt.line[length - 1] == '\\r') {
                  length -= 1;
              }
              bareruby_uart_interrupt.line[length] = '\\0';
              bareruby_uart_interrupt.line_length = 0;
              bareruby_uart_interrupt_trace_line(bareruby_uart_interrupt.line, length);
              if (bareruby_uart_interrupt.handler != NULL) {
                  bareruby_string_view_t view = {bareruby_uart_interrupt.line, length};
                  bareruby_uart_interrupt.handler(&view);
              }
              return;
          }
          if (bareruby_uart_interrupt.discarding) {
              return;
          }
          if (bareruby_uart_interrupt.line_length == 255) {   /* a line is at most 255 bytes */
              bareruby_uart_interrupt.discarding = true;
              bareruby_uart_interrupt.line_length = 0;
              return;
          }
          bareruby_uart_interrupt.line[bareruby_uart_interrupt.line_length++] = (char)byte;
      }

      /* The ring has one consumer. A registered handler is it, and the drain assembles
         lines; without one the bytes wait for the read family below. */
      extern "C" void bareruby_uart_interrupt_drain(void) {
          if (!bareruby_uart_interrupt.attached) {
              return;
          }
          bareruby_uart_interrupt_pump();
          if (bareruby_uart_interrupt.handler == NULL) {
              return;
          }
          while (bareruby_uart_interrupt.tail != bareruby_uart_interrupt.head) {
              uint8_t byte = bareruby_uart_interrupt.data[bareruby_uart_interrupt.tail];
              bareruby_uart_interrupt.tail = (uint8_t)(bareruby_uart_interrupt.tail + 1u);
              bareruby_uart_interrupt_line_byte(byte);
          }
      }

      void bareruby_uart_on_line(bareruby_uart_t *self, bareruby_uart_line_handler_t handler) {
          bareruby_uart_interrupt.handler = handler;
          bareruby_uart_interrupt_pump();
          fprintf(stderr, "uart_on_line(id=%d)\\n", (int)self->id);
      }

      int32_t bareruby_uart_read_byte(bareruby_uart_t *self) {
          bareruby_uart_interrupt_pump();
          if (bareruby_uart_interrupt.tail == bareruby_uart_interrupt.head) {
              fprintf(stderr, "uart_read_byte(id=%d) -> -1\\n", (int)self->id);
              return -1;
          }
          uint8_t byte = bareruby_uart_interrupt.data[bareruby_uart_interrupt.tail];
          bareruby_uart_interrupt.tail = (uint8_t)(bareruby_uart_interrupt.tail + 1u);
          fprintf(stderr, "uart_read_byte(id=%d) -> %d\\n", (int)self->id, (int)byte);
          return (int32_t)byte;
      }

      int32_t bareruby_uart_peek(bareruby_uart_t *self) {
          bareruby_uart_interrupt_pump();
          if (bareruby_uart_interrupt.tail == bareruby_uart_interrupt.head) {
              fprintf(stderr, "uart_peek(id=%d) -> -1\\n", (int)self->id);
              return -1;
          }
          int32_t byte = (int32_t)bareruby_uart_interrupt.data[bareruby_uart_interrupt.tail];
          fprintf(stderr, "uart_peek(id=%d) -> %d\\n", (int)self->id, (int)byte);
          return byte;
      }

      /* The strong definition; the polling one in the uart unit is weak. */
      int32_t bareruby_uart_bytes_available(bareruby_uart_t *self) {
          bareruby_uart_interrupt_pump();
          int32_t depth =
              (int32_t)(uint8_t)(bareruby_uart_interrupt.head - bareruby_uart_interrupt.tail);
          fprintf(stderr, "uart_bytes_available(id=%d) -> %d\\n", (int)self->id, (int)depth);
          return depth;
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

    PWM_FILE = "bareruby_binding_pwm_host.cpp"
    ADC_FILE = "bareruby_binding_adc_host.cpp"
    UART_FILE = "bareruby_binding_uart_host.cpp"
    GPIO_FILE = "bareruby_binding_gpio_host.cpp"
    PERIPHERAL_FILE = "bareruby_binding_host.cpp"
    UART_RECEIVE_FILE = "bareruby_binding_uart_receive_host.cpp"
    UART_INTERRUPT_FILE = "bareruby_binding_uart_interrupt_host.cpp"
    I2C_FILE = "bareruby_binding_i2c_host.cpp"
    I2C_READ_FILE = "bareruby_binding_i2c_read_host.cpp"

    # A machine with no indicator to reach answers all the same, so that whether a
    # board has one never decides whether a program compiles.
    ONBOARD_LED_NONE = <<~CPP
      #include "bareruby_binding.h"

      #include <stdio.h>

      void bareruby_onboard_led_init(bareruby_onboard_led_t *self) {
          self->state = 0;
          fprintf(stderr, "onboard_led_init()\\n");
      }

      void bareruby_onboard_led_write(bareruby_onboard_led_t *self, int32_t value) {
          self->state = (value != 0) ? 1 : 0;
          fprintf(stderr, "onboard_led_write(value=%d)\\n", (int)self->state);
      }

      void bareruby_onboard_led_on(bareruby_onboard_led_t *self) {
          bareruby_onboard_led_write(self, 1);
      }

      void bareruby_onboard_led_off(bareruby_onboard_led_t *self) {
          bareruby_onboard_led_write(self, 0);
      }
    CPP

    ONBOARD_LED_NONE_FILE = "bareruby_binding_onboard_led_host_none.cpp"

    FILES = {
      GPIO_FILE => GPIO,
      ADC_FILE => ADC,
      UART_FILE => UART,
      PWM_FILE => PWM,
      PERIPHERAL_FILE => PERIPHERAL,
      UART_RECEIVE_FILE => UART_RECEIVE,
      UART_INTERRUPT_FILE => UART_INTERRUPT,
      I2C_FILE => I2C,
      I2C_READ_FILE => I2C_READ,
      ONBOARD_LED_NONE_FILE => ONBOARD_LED_NONE
    }.freeze

    # What a peripheral asks for by key, this binding answers with a file. The key is the
    # peripheral's word and the file is this side's, so neither has to know the other.
    UNITS = { onboard_led: :onboard_led_file, gpio: GPIO_FILE, adc: ADC_FILE, uart: UART_FILE, uart_receive: UART_RECEIVE_FILE, uart_interrupt: UART_INTERRUPT_FILE, pwm: PWM_FILE, i2c: I2C_FILE, i2c_read: I2C_READ_FILE }.freeze

    # A unit is usually one file. **Some are the machine's answer instead** — an
    # indicator is reached through a pin on one board and through a radio on another, so
    # the key resolves to a question rather than a name, and the cell beside this file
    # answers it.
    def self.unit(key, machine)
      found = UNITS.fetch(key)
      found.is_a?(Symbol) ? machine(machine).public_send(found) : found
    end

    ALWAYS = [PERIPHERAL_FILE].freeze


    # What a machine takes is not worked out here. Each machine this binding reaches
    # writes its own answer as a method, in machine/ beside this file, and this only hands
    # the question over. A machine it cannot reach has no answer rather than a wrong one.
    MACHINES = {}

    def self.machine(machine) = MACHINES.fetch(machine.key)

    # Nothing on the other side of this build owns main, so the program's own translation
    # unit carries the entry point and is named for it.
    PROGRAM_FILE = "main.cpp"

    def self.key = :host

    # **No toolchain of its own**, which is what keeps this binding on one side of the
    # line. One g++ invocation is what the manifest already says in full, so there is
    # nothing left for a toolchain here to add — and a toolchain is where a binding would
    # reach for the side of this that runs the second stage. This one never has to.

    def self.flash = HostFlash

    def self.build = HostBuild
  end
end

# One machine to a file, so that teaching this binding a new machine is adding a file.
Dir.children(File.expand_path("machine", __dir__)).sort.grep(/\.rb\z/).each do |entry|
  require_relative "machine/#{entry}"
end
