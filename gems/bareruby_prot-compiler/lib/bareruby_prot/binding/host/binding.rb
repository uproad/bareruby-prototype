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

      void bareruby_pwm_apply_frequency(bareruby_pwm_t *self, int32_t frequency) {
          self->frequency = frequency;
          fprintf(stderr, "pwm_frequency(pin=%d, frequency=%d)\\n", (int)self->pin, (int)frequency);
      }

      void bareruby_pwm_apply_period_us(bareruby_pwm_t *self, int32_t period_us) {
          fprintf(stderr, "pwm_period_us(pin=%d, period_us=%d)\\n", (int)self->pin, (int)period_us);
      }

      void bareruby_pwm_apply_duty(bareruby_pwm_t *self, int32_t duty) {
          fprintf(stderr, "pwm_duty(pin=%d, duty=%d)\\n", (int)self->pin, (int)duty);
      }

      void bareruby_pwm_apply_pulse_width_us(bareruby_pwm_t *self, int32_t pulse_width_us) {
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

      static void bareruby_trace_escaped(const char *text) {
          for (const char *cursor = text; *cursor != '\\0'; ++cursor) {
              if (*cursor == '\\n') {
                  fputs("\\\\n", stderr);
              } else if (*cursor == '\\r') {
                  fputs("\\\\r", stderr);
              } else {
                  fputc(*cursor, stderr);
              }
          }
      }

      /* The ending is traced beside the text rather than left implied by the label,
         because what a line ends with is the program's to choose now. */
      static void bareruby_trace_payload(const char *label, const bareruby_uart_t *self,
                                         const char *text, const char *ending) {
          fprintf(stderr, "%s(unit=%d, text=\\"", label, (int)self->unit);
          bareruby_trace_escaped(text);
          bareruby_trace_escaped(ending);
          fputs("\\")\\n", stderr);
      }

      /* What the line is opened with, traced. The constructor and setmode differ only in
         where the values came from, so both end here and say which they were. */
      static void bareruby_uart_apply(const bareruby_uart_t *self, const char *label) {
          fprintf(stderr,
                  "%s(unit=%d, txd_pin=%d, rxd_pin=%d, baudrate=%d, data_bits=%d, "
                  "stop_bits=%d, parity=%d, flow_control=%d, rts_pin=%d, cts_pin=%d)\\n",
                  label, (int)self->unit, (int)self->txd_pin, (int)self->rxd_pin,
                  (int)self->baudrate, (int)self->data_bits, (int)self->stop_bits,
                  (int)self->parity, (int)self->flow_control, (int)self->rts_pin,
                  (int)self->cts_pin);
      }

      void bareruby_uart_init(
          bareruby_uart_t *self, int32_t unit, int32_t txd_pin, int32_t rxd_pin,
          int32_t baudrate, int32_t data_bits, int32_t stop_bits, int32_t parity,
          int32_t flow_control, int32_t rts_pin, int32_t cts_pin) {
          self->unit = unit;
          self->txd_pin = txd_pin;
          self->rxd_pin = rxd_pin;
          self->baudrate = baudrate;
          self->data_bits = data_bits;
          self->stop_bits = stop_bits;
          self->parity = parity;
          self->flow_control = flow_control;
          self->rts_pin = rts_pin;
          self->cts_pin = cts_pin;
          self->line_ending = "\\n";
          bareruby_uart_apply(self, "uart_init");
      }

      void bareruby_uart_setmode(
          bareruby_uart_t *self, int32_t baudrate, int32_t data_bits, int32_t stop_bits,
          int32_t parity, int32_t flow_control, int32_t rts_pin, int32_t cts_pin) {
          bareruby_uart_settle(self, baudrate, data_bits, stop_bits, parity, flow_control,
                               rts_pin, cts_pin);
          bareruby_uart_apply(self, "uart_setmode");
      }

      int32_t bareruby_uart_write(bareruby_uart_t *self, const char *value) {
          bareruby_trace_payload("uart_write", self, value, "");
          return (int32_t)strlen(value);
      }

      /* **What ends a line is the line's, not the compiler's.** puts puts the ending the
         class was given; write puts nothing after what it was handed, whether or not the
         program wrote an interpolation. */
      void bareruby_uart_puts(bareruby_uart_t *self, const char *value) {
          bareruby_trace_payload("uart_puts", self, value, self->line_ending);
      }

      void bareruby_uart_printf(bareruby_uart_t *self, const char *format, ...) {
          char payload[256];
          va_list arguments;
          va_start(arguments, format);
          vsnprintf(payload, sizeof(payload), format, arguments);
          va_end(arguments);
          bareruby_trace_payload("uart_printf", self, payload, "");
      }

      void bareruby_uart_printf_line(bareruby_uart_t *self, const char *format, ...) {
          char payload[256];
          va_list arguments;
          va_start(arguments, format);
          vsnprintf(payload, sizeof(payload), format, arguments);
          va_end(arguments);
          bareruby_trace_payload("uart_printf_line", self, payload, self->line_ending);
      }

      /* Weak, so the uart_interrupt unit's ring-backed answer replaces this one the
         moment a program touches the buffered receive side. */
      __attribute__((weak)) int32_t bareruby_uart_bytes_available(bareruby_uart_t *self) {
          fprintf(stderr, "uart_bytes_available(unit=%d) -> 0\\n", (int)self->unit);
          return 0;
      }

      void bareruby_uart_flush(bareruby_uart_t *self) {
          fprintf(stderr, "uart_flush(unit=%d)\\n", (int)self->unit);
      }

      /* Nothing is held back here: a write reaches the descriptor before it returns, so
         the send side owes the wire nothing by the time this can be asked. */
      int32_t bareruby_uart_bytes_to_write(bareruby_uart_t *self) {
          fprintf(stderr, "uart_bytes_to_write(unit=%d) -> 0\\n", (int)self->unit);
          return 0;
      }

      void bareruby_uart_break(bareruby_uart_t *self, int32_t milliseconds) {
          fprintf(stderr, "uart_break(unit=%d, milliseconds=%d)\\n",
                  (int)self->unit, (int)milliseconds);
      }

      /* Weak for the same reason as bytes_available: once the receive queue exists it is
         what the receive buffer is, and the uart_receive unit empties that instead. */
      __attribute__((weak)) void bareruby_uart_clear_rx_buffer(bareruby_uart_t *self) {
          fprintf(stderr, "uart_clear_rx_buffer(unit=%d)\\n", (int)self->unit);
      }

      void bareruby_uart_clear_tx_buffer(bareruby_uart_t *self) {
          fprintf(stderr, "uart_clear_tx_buffer(unit=%d)\\n", (int)self->unit);
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

      int32_t bareruby_gpio_write(bareruby_gpio_t *self, int32_t value) {
          fprintf(stderr, "gpio_write(pin=%d, value=%d)\\n", (int)self->pin, (int)value);
          return 0;
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

      void bareruby_gpio_irq(
          bareruby_gpio_t *self, int32_t events, bareruby_interrupt_handler_t handler) {
          fprintf(stderr, "gpio_irq(pin=%d, events=%d)\\n", (int)self->pin, (int)events);
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

      /* The uart_interrupt unit overrides this when a program registers an irq;
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

      int32_t bareruby_sleep(int32_t seconds, bool interrupt) {
          fprintf(stderr, "sleep(seconds=%d, interrupt=%s)\\n", (int)seconds,
                  bareruby_wait_interrupt(interrupt));
          bareruby_wait_deliver(interrupt);
          return seconds;
      }

      int32_t bareruby_sleep_ms(int32_t milliseconds, bool interrupt) {
          fprintf(stderr, "sleep_ms(milliseconds=%d, interrupt=%s)\\n", (int)milliseconds,
                  bareruby_wait_interrupt(interrupt));
          bareruby_wait_deliver(interrupt);
          return milliseconds;
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

      #include <fcntl.h>
      #include <stdio.h>
      #include <unistd.h>

      /* **The one queue the receive side has.** stdin is the wire; filling from it stands
         in for the interrupt, and whoever asks first takes what is in the queue. A handler
         and a program calling getbyte are the same kind of consumer, reaching it through
         the same call. */
      /* What this binding gives when the program did not ask. A program that asks reaches
         the same name from the header, settled where the call was written. */
      #ifndef BARERUBY_UART_RX_BUFFER_SIZE
      #define BARERUBY_UART_RX_BUFFER_SIZE 256
      #endif

      typedef struct {
          uint8_t data[BARERUBY_UART_RX_BUFFER_SIZE];   /* what the receive side costs */
          uint16_t head;
          uint16_t tail;
          bool attached;
      } bareruby_uart_receive_t;

      static bareruby_uart_receive_t bareruby_uart_receive;

      /* The indices count entries rather than wrapping a byte, because how many entries
         there are is the program's answer now and is not always 256. */
      static uint16_t bareruby_uart_receive_next(uint16_t index) {
          uint16_t next = (uint16_t)(index + 1u);
          return next == BARERUBY_UART_RX_BUFFER_SIZE ? (uint16_t)0u : next;
      }

      static void bareruby_uart_receive_push(uint8_t byte) {
          uint16_t next = bareruby_uart_receive_next(bareruby_uart_receive.head);
          if (next == bareruby_uart_receive.tail) {
              return;   /* a full queue drops the byte, and says nothing */
          }
          bareruby_uart_receive.data[bareruby_uart_receive.head] = byte;
          bareruby_uart_receive.head = next;
      }

      /* What the interrupt does on a board: move whatever the line has delivered into the
         queue. Here the line is stdin, read without blocking so that a wire saying nothing
         is not the same as a program stopping. */
      static void bareruby_uart_receive_fill(bareruby_uart_t *self) {
          if (!bareruby_uart_receive.attached) {
              bareruby_uart_receive.attached = true;
              fcntl(STDIN_FILENO, F_SETFL, fcntl(STDIN_FILENO, F_GETFL) | O_NONBLOCK);
          }
          unsigned char chunk[64];
          for (;;) {
              ssize_t received = read(STDIN_FILENO, chunk, sizeof(chunk));
              if (received <= 0) {
                  break;
              }
              for (ssize_t index = 0; index < received; ++index) {
                  bareruby_uart_receive_push(chunk[index]);
              }
          }
      }

      int32_t bareruby_uart_getbyte(bareruby_uart_t *self) {
          bareruby_uart_receive_fill(self);
          if (bareruby_uart_receive.tail == bareruby_uart_receive.head) {
              fprintf(stderr, "uart_getbyte(unit=%d) -> -1\\n", (int)self->unit);
              return -1;
          }
          uint8_t byte = bareruby_uart_receive.data[bareruby_uart_receive.tail];
          bareruby_uart_receive.tail = bareruby_uart_receive_next(bareruby_uart_receive.tail);
          fprintf(stderr, "uart_getbyte(unit=%d) -> %d\\n", (int)self->unit, (int)byte);
          return (int32_t)byte;
      }

      int32_t bareruby_uart_peek(bareruby_uart_t *self) {
          bareruby_uart_receive_fill(self);
          if (bareruby_uart_receive.tail == bareruby_uart_receive.head) {
              fprintf(stderr, "uart_peek(unit=%d) -> -1\\n", (int)self->unit);
              return -1;
          }
          int32_t byte = (int32_t)bareruby_uart_receive.data[bareruby_uart_receive.tail];
          fprintf(stderr, "uart_peek(unit=%d) -> %d\\n", (int)self->unit, (int)byte);
          return byte;
      }

      /* The strong definitions; the polling ones in the uart unit are weak. Once the queue
         exists it is what the receive side is, so emptying the buffer empties it. */
      int32_t bareruby_uart_bytes_available(bareruby_uart_t *self) {
          bareruby_uart_receive_fill(self);
          uint16_t head = bareruby_uart_receive.head;
          uint16_t tail = bareruby_uart_receive.tail;
          int32_t depth = (int32_t)(head >= tail ? head - tail : head + BARERUBY_UART_RX_BUFFER_SIZE - tail);
          fprintf(stderr, "uart_bytes_available(unit=%d) -> %d\\n", (int)self->unit, (int)depth);
          return depth;
      }

      void bareruby_uart_clear_rx_buffer(bareruby_uart_t *self) {
          bareruby_uart_receive_fill(self);
          bareruby_uart_receive.tail = bareruby_uart_receive.head;
          fprintf(stderr, "uart_clear_rx_buffer(unit=%d)\\n", (int)self->unit);
      }
    CPP

    # The receive side an interrupt feeds, hosted: there is no wire to interrupt from, so
    # the first touch — a registration or a buffered read — puts stdin into non-blocking
    # mode, and the pump plays the ISR's part, reading whatever has arrived into the ring.
    # With a handler registered the drain assembles lines exactly as a board does, so
    # CRLF, the 255-byte cap and the overlong discard behave byte for byte the same;
    # without one the bytes stay in the ring for getbyte, peek and bytes_available.
    UART_INTERRUPT = <<~CPP
      #include "bareruby_binding.h"

      #include <stdio.h>

      /* **The notification says which port and which event, and stops there.** What
         arrived is in the queue, and the handler takes it with the same call a program
         would; nothing here knows what a line is. The registration is remembered rather
         than handed to the interrupt, because the handler runs in thread mode — a wait is
         where it gets to run, and a wait is where the drain below is called from. */
      static bareruby_uart_irq_handler_t bareruby_uart_irq_handler;
      static bareruby_uart_t *bareruby_uart_irq_port;
      static int32_t bareruby_uart_irq_events;

      void bareruby_uart_irq(
          bareruby_uart_t *self, int32_t events, bareruby_uart_irq_handler_t handler) {
          bareruby_uart_irq_handler = handler;
          bareruby_uart_irq_port = self;
          bareruby_uart_irq_events = events;
          fprintf(stderr, "uart_irq(unit=%d, events=%d)\\n", (int)self->unit, (int)events);
          bareruby_uart_bytes_available(self);   /* the touch that arms the receive side */
      }

      /* One event exists, so what was registered for and what fired are the same value.
         The day there is a second, this is where the two have to be told apart. */
      extern "C" void bareruby_uart_interrupt_drain(void) {
          if (bareruby_uart_irq_port == NULL) {
              return;
          }
          if (bareruby_uart_bytes_available(bareruby_uart_irq_port) == 0) {
              return;
          }
          bareruby_uart_irq_handler(bareruby_uart_irq_port, bareruby_uart_irq_events);
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

      void bareruby_i2c_init(bareruby_i2c_t *self, int32_t unit, int32_t frequency) {
          self->unit = unit;
          self->frequency = frequency;
          fprintf(stderr, "i2c_init(unit=%d, frequency=%d)\\n", (int)unit, (int)frequency);
      }

      int32_t bareruby_i2c_write(
          bareruby_i2c_t *self, int32_t address, const char *bytes, int32_t length) {
          fprintf(stderr, "i2c_write(unit=%d, address=0x%02x, bytes=",
                  (int)self->unit, (unsigned int)address);
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
          fprintf(stderr, "i2c_read(unit=%d, address=0x%02x, length=%d, outputs=",
                  (int)self->unit, (unsigned int)address, (int)length);
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

    # **A board to run against, where there is no board.** The build already runs on the
    # machine that made it, so what an emulator adds here is the peripherals: a run under
    # the simulator answers a pin from a pin rather than from a stub that prints.
    def self.emulate = HostEmulate

    def self.flash = HostFlash

    def self.build = HostBuild
  end
end

# One machine to a file, so that teaching this binding a new machine is adding a file.
Dir.children(File.expand_path("machine", __dir__)).sort.grep(/\.rb\z/).each do |entry|
  require_relative "machine/#{entry}"
end
