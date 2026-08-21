# frozen_string_literal: true

module BareRubyProt
  module PicoSdkBinding
    # GPIO in its own translation unit. **A peripheral that can be uninstalled cannot
    # share a file with one that cannot** — the declarations go with the gem, and an
    # implementation left behind would have nothing to implement against.
    PWM = <<~CPP
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
    CPP

    ADC = <<~CPP
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
    CPP

    UART = <<~CPP
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

      void bareruby_uart_init(
          bareruby_uart_t *self, int32_t id, int32_t baud,
          int32_t data_bits, int32_t stop_bits, int32_t parity) {
          self->id = id;
          self->baud = baud;
          self->data_bits = data_bits;
          self->stop_bits = stop_bits;
          self->parity = parity;
          uart_inst_t *port = (id == 0) ? uart0 : uart1;
          uart_init(port, (uint)baud);
          /* The PL011 takes the data bits as their own field, 5 through 8, so the frame
             asked for goes straight through. */
          uart_set_format(port, (uint)data_bits, stop_bits == 2 ? 2 : 1,
                          parity == 1 ? UART_PARITY_EVEN
                                      : (parity == 2 ? UART_PARITY_ODD : UART_PARITY_NONE));
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

      /* Weak, so the uart_interrupt unit's ring-backed answer replaces this one the
         moment a program touches the buffered receive side. */
      __attribute__((weak)) int32_t bareruby_uart_bytes_available(bareruby_uart_t *self) {
          return uart_is_readable(bareruby_uart_port(self)) ? 1 : 0;
      }

      /* The SDK writes by blocking, so nothing waits behind the call. What can still be
         owed is what the transmit FIFO holds: BUSY stays set while it drains. */
      int32_t bareruby_uart_bytes_to_write(bareruby_uart_t *self) {
          return (uart_get_hw(bareruby_uart_port(self))->fr & UART_UARTFR_BUSY_BITS) ? 1 : 0;
      }

      /* The PL011 holds the line low for as long as BRK is set, so the requested span is
         served exactly. */
      void bareruby_uart_send_break(bareruby_uart_t *self, int32_t milliseconds) {
          uart_inst_t *port = bareruby_uart_port(self);
          uart_tx_wait_blocking(port);
          hw_set_bits(&uart_get_hw(port)->lcr_h, UART_UARTLCR_H_BRK_BITS);
          sleep_ms((uint32_t)(milliseconds > 0 ? milliseconds : 0));
          hw_clear_bits(&uart_get_hw(port)->lcr_h, UART_UARTLCR_H_BRK_BITS);
      }

      void bareruby_uart_flush(bareruby_uart_t *self) {
          uart_tx_wait_blocking(bareruby_uart_port(self));
      }

      /* Weak for the same reason as bytes_available: once the receive queue exists it is
         what the receive buffer is, and the uart_receive unit empties that instead. */
      __attribute__((weak)) void bareruby_uart_clear_rx_buffer(bareruby_uart_t *self) {
          while (uart_is_readable(bareruby_uart_port(self))) {
              (void)uart_getc(bareruby_uart_port(self));
          }
      }

      void bareruby_uart_clear_tx_buffer(bareruby_uart_t *self) {
          uart_tx_wait_blocking(bareruby_uart_port(self));
      }
    CPP

    GPIO = <<~CPP
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

      static bareruby_interrupt_handler_t bareruby_gpio_interrupt_handler;

      static void bareruby_gpio_interrupt_callback(uint gpio, uint32_t events) {
          (void)gpio;
          (void)events;
          bareruby_gpio_interrupt_handler();
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

      void bareruby_gpio_on_interrupt(
          bareruby_gpio_t *self, int32_t events, bareruby_interrupt_handler_t handler) {
          bareruby_gpio_interrupt_handler = handler;
          gpio_set_irq_enabled_with_callback(
              (uint)self->pin, (uint32_t)events, true, bareruby_gpio_interrupt_callback);
      }
    CPP

    PERIPHERAL = <<~CPP
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

      /* The identity unit defines this where there is a USB channel to listen on. A
         release firmware presents none, so the default stands and nothing is started. */
      extern "C" __attribute__((weak)) void bareruby_agent_start(void) {}

      void bareruby_startup(void) {
          stdio_init_all();
          bareruby_agent_start();
      }

      /* The uart_interrupt unit overrides this when a program registers an irq;
         sleep drains nothing and pays one empty call per millisecond. */
      extern "C" __attribute__((weak)) void bareruby_uart_interrupt_drain(void) {}

      void bareruby_machine_delay_us(int32_t microseconds) {
          sleep_us((uint64_t)microseconds);
      }

      /* The wait is counted unsigned, as the asleep mark below is, so that the seconds
         form can turn its argument into milliseconds without overflowing a signed
         multiplication. */
      static void bareruby_sleep_for(uint32_t milliseconds, bool interrupt) {
          absolute_time_t deadline = make_timeout_time_ms(milliseconds);
          for (;;) {
              if (interrupt) {
                  bareruby_uart_interrupt_drain();
              }
              if (time_reached(deadline)) {
                  break;
              }
              sleep_ms(1);
          }
      }

      void bareruby_sleep_ms(int32_t milliseconds, bool interrupt) {
          bareruby_sleep_for(milliseconds > 0 ? (uint32_t)milliseconds : 0u, interrupt);
      }

      void bareruby_sleep(int32_t seconds, bool interrupt) {
          bareruby_sleep_for(seconds > 0 ? (uint32_t)seconds * 1000u : 0u, interrupt);
      }

      // One mark serves all three units, and it counts microseconds since boot in 64
      // bits: 32 would wrap after 71 minutes, which the seconds form is meant to
      // outlast. Zero is boot time, so the first call needs no flag of its own. A late
      // turn does not try to catch up — the mark moves to the actual return and the
      // missed time is gone, which keeps one slow turn from firing the next ones back
      // to back.
      static uint64_t bareruby_asleep_mark = 0;

      // **A period is only long enough to deliver in if it is longer than delivering
      // takes.** So the wait is spent in whole milliseconds while more than one of them
      // remains, and what is left is one exact wait to the deadline: a 25 us period keeps
      // its exactness and delivers nothing, which is the honest answer for a period that
      // has no room for a handler. Notifications are not lost by it — the interrupt keeps
      // filling the queue, and the next wait long enough will hand them over.
      static void bareruby_asleep_until(uint64_t interval, bool interrupt) {
          uint64_t deadline = bareruby_asleep_mark + interval;
          while (interrupt && time_us_64() + 1000u < deadline) {
              bareruby_uart_interrupt_drain();
              sleep_ms(1);
          }
          if (time_us_64() < deadline) {
              sleep_until(from_us_since_boot(deadline));
          }
          bareruby_asleep_mark = time_us_64();
      }

      void bareruby_asleep(int32_t seconds, bool interrupt) {
          bareruby_asleep_until((uint64_t)seconds * 1000000u, interrupt);
      }

      void bareruby_asleep_ms(int32_t milliseconds, bool interrupt) {
          bareruby_asleep_until((uint64_t)milliseconds * 1000u, interrupt);
      }

      void bareruby_asleep_us(int32_t microseconds, bool interrupt) {
          bareruby_asleep_until((uint64_t)microseconds, interrupt);
      }

      int32_t bareruby_ticks_ms(void) {
          return (int32_t)to_ms_since_boot(get_absolute_time());
      }
    CPP

    UART_RECEIVE = <<~CPP
      #include "bareruby_binding.h"

      #include "hardware/irq.h"
      #include "hardware/uart.h"

      /* **The one queue the receive side has.** The interrupt fills it from the line, and
         whoever asks first takes what is in it: a registered handler and a program calling
         read_byte are the same kind of consumer, reaching the queue through the same call.
         What is not taken is nobody else's loss. */
      /* What this binding gives when the program did not ask. A program that asks reaches
         the same name from the header, settled where the call was written. */
      #ifndef BARERUBY_UART_RX_BUFFER_SIZE
      #define BARERUBY_UART_RX_BUFFER_SIZE 256
      #endif

      typedef struct {
          volatile uint8_t data[BARERUBY_UART_RX_BUFFER_SIZE];   /* what the receive side costs */
          volatile uint16_t head;       /* interrupt-owned */
          volatile uint16_t tail;       /* consumer-owned */
          uart_inst_t *port;
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

      static void bareruby_uart_receive_isr(void) {
          uart_inst_t *port = bareruby_uart_receive.port;
          while (uart_is_readable(port)) {
              /* The FIFO's data register carries the error flags beside the byte; a
                 byte whose parity failed is discarded, as Arduino's core does. */
              uint32_t entry = uart_get_hw(port)->dr;
              if ((entry & UART_UARTDR_PE_BITS) == 0u) {
                  bareruby_uart_receive_push((uint8_t)(entry & 0xFFu));
              }
          }
      }

      /* The first touch of the receive side — a registration or a read — is what arms the
         interrupt and so what buys the queue. */
      static void bareruby_uart_receive_attach(bareruby_uart_t *self) {
          if (bareruby_uart_receive.port != NULL) {
              return;
          }
          uart_inst_t *port = (self->id == 0) ? uart0 : uart1;
          uint irq = (self->id == 0) ? UART0_IRQ : UART1_IRQ;
          bareruby_uart_receive.port = port;   /* published before the IRQ can fire */
          irq_set_exclusive_handler(irq, bareruby_uart_receive_isr);
          irq_set_enabled(irq, true);
          /* RX on, TX off. This also arms the receive-timeout interrupt, so a line
             shorter than the FIFO watermark still arrives promptly. */
          uart_set_irq_enables(port, true, false);
      }

      int32_t bareruby_uart_read_byte(bareruby_uart_t *self) {
          bareruby_uart_receive_attach(self);
          if (bareruby_uart_receive.tail == bareruby_uart_receive.head) {
              return -1;
          }
          uint8_t byte = bareruby_uart_receive.data[bareruby_uart_receive.tail];
          bareruby_uart_receive.tail = bareruby_uart_receive_next(bareruby_uart_receive.tail);
          return (int32_t)byte;
      }

      int32_t bareruby_uart_peek(bareruby_uart_t *self) {
          bareruby_uart_receive_attach(self);
          if (bareruby_uart_receive.tail == bareruby_uart_receive.head) {
              return -1;
          }
          return (int32_t)bareruby_uart_receive.data[bareruby_uart_receive.tail];
      }

      /* The strong definitions; the polling ones in the uart unit are weak. Once the queue
         exists it is what the receive side is, so emptying the buffer empties it. */
      int32_t bareruby_uart_bytes_available(bareruby_uart_t *self) {
          bareruby_uart_receive_attach(self);
          uint16_t head = bareruby_uart_receive.head;
          uint16_t tail = bareruby_uart_receive.tail;
          return (int32_t)(head >= tail ? head - tail : head + BARERUBY_UART_RX_BUFFER_SIZE - tail);
      }

      void bareruby_uart_clear_rx_buffer(bareruby_uart_t *self) {
          bareruby_uart_receive_attach(self);
          bareruby_uart_receive_isr();   /* whatever the line has already sent */
          bareruby_uart_receive.tail = bareruby_uart_receive.head;
      }
    CPP

    # The receive interrupt. The ISR does one thing — move what the FIFO holds into a
    # 256-byte ring — and every policy (LF/CRLF framing, the 255-byte cap, the overlong
    # discard, the handler itself) runs in thread mode when sleep drains the ring. One
    # producer, one consumer, single-byte indices that wrap by uint8_t overflow: no
    # critical section is needed on a Cortex-M0+ or M33.
    UART_INTERRUPT = <<~CPP
      #include "bareruby_binding.h"

      #include <stddef.h>

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

    I2C_READ = <<~CPP
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

    # **What the board is called, and the board saying it.**
    #
    # A Pico announces itself over USB as "Pico", made by "Raspberry Pi", and — in its
    # bootloader — as a serial number three identical boards on one desk all answer to.
    # There is nothing in that a desk can point at. So the name a target is recorded under
    # is written into the board itself, and the board hands it back as its USB serial
    # number: the desk asks for a name and gets the board that was given it.
    #
    # The name is data rather than code. It sits in a page of flash that no image reaches,
    # is written once by `target attach`, and survives every program flashed afterwards —
    # so one firmware serves every board and no build has to be told which board it is for.
    #
    # pico-sdk writes the USB descriptors itself unless the build says otherwise, and the
    # build says otherwise only where there is a USB interface at all. A release firmware
    # presents none, which is why the whole of this is asked of LIB_PICO_STDIO_USB: a board
    # with nothing to speak on has no name to say.
    #
    # **It reaches for nothing this compiler made.** Every other unit here is written beside
    # a program and includes the declarations that program generated. This one is about the
    # board rather than about any program, which is what lets the agent `target attach`
    # writes carry it with no program anywhere near it.
    # **TinyUSB is configured by a header it finds, and pico-sdk ships one that answers
    # for it.** That answer turns the vendor class off — pico-sdk reaches its own vendor
    # interface with a driver of its own and needs no more — so a board that wants BRDF's
    # pipe has to answer first. Written beside the CMakeLists that names it, on an include
    # path put ahead of the SDK's; `#include_next` then reaches the SDK's own answer and
    # only the one line that has to differ is changed.
    #
    # It has to be found by TinyUSB's own sources as well as by this side's, which is why
    # it is an include directory on the target rather than a define: pico-sdk links
    # TinyUSB as an interface library, so its units are compiled into this target and see
    # this target's include path.
    TUSB_CONFIG_FILE = "tusb_config.h"

    TUSB_CONFIG = <<~CPP
      #ifndef BARERUBY_TUSB_CONFIG_H
      #define BARERUBY_TUSB_CONFIG_H

      #include_next <tusb_config.h>

      #undef CFG_TUD_VENDOR
      #define CFG_TUD_VENDOR (1)
      #define CFG_TUD_VENDOR_RX_BUFSIZE (64)
      #define CFG_TUD_VENDOR_TX_BUFSIZE (64)

      #endif
    CPP

    IDENTITY = <<~CPP
      #if LIB_PICO_STDIO_USB

      #include <stdio.h>
      #include <string.h>

      #include "hardware/flash.h"
      #include "hardware/sync.h"
      #include "pico/flash.h"
      #include "pico/unique_id.h"
      #include "pico/usb_reset.h"
      #include "tusb.h"

      /* The reserved page is the first page of the last sector of this board's flash. The
         board header sizes the flash, so one expression names the end of a 2 MB Pico and
         of a 4 MB Pico 2 without either being spelled out here, and the largest image
         measured — 553 KB, a Pico 2 W carrying the radio's firmware — is nowhere near it. */
      #define BARERUBY_NAME_PAGE (XIP_BASE + PICO_FLASH_SIZE_BYTES - FLASH_SECTOR_SIZE)

      /* An erased sector reads 0xFF throughout, so a board that has never been attached
         says so by not carrying the mark, and answers with the chip's own id instead. */
      #define BARERUBY_NAME_MARK "BARERUBY"
      #define BARERUBY_NAME_MARK_LENGTH 8

      /* The attach agent carries the requested name in RAM first, so its USB descriptor
         can say the right thing without asking a bootloader to update a used flash page.
         Once USB is up, the same safe flash mechanism resident deploy uses persists the
         page. Programs deployed afterwards simply keep reading it. */
      static uint8_t bareruby_attached_page[FLASH_PAGE_SIZE];
      static bool bareruby_attaching;

      extern "C" void bareruby_agent_attach(const uint8_t *name, size_t length) {
          uint32_t byte;
          if (length > FLASH_PAGE_SIZE - BARERUBY_NAME_MARK_LENGTH - 1) {
              length = FLASH_PAGE_SIZE - BARERUBY_NAME_MARK_LENGTH - 1;
          }
          for (byte = 0; byte < FLASH_PAGE_SIZE; ++byte) {
              bareruby_attached_page[byte] = 0xff;
          }
          for (byte = 0; byte < BARERUBY_NAME_MARK_LENGTH; ++byte) {
              bareruby_attached_page[byte] = BARERUBY_NAME_MARK[byte];
          }
          for (byte = 0; byte < length; ++byte) {
              bareruby_attached_page[BARERUBY_NAME_MARK_LENGTH + byte] = name[byte];
          }
          bareruby_attached_page[BARERUBY_NAME_MARK_LENGTH + length] = 0;
          bareruby_attaching = true;
      }

      static void bareruby_attach_erase(void *offset) {
          flash_range_erase(*(uint32_t *)offset, FLASH_SECTOR_SIZE);
      }

      static void bareruby_attach_program(void *offset) {
          flash_range_program(*(uint32_t *)offset,
                              bareruby_attached_page, FLASH_PAGE_SIZE);
      }

      extern "C" void bareruby_persist_attached_name(void) {
          if (!bareruby_attaching ||
              memcmp((const void *)BARERUBY_NAME_PAGE,
                     bareruby_attached_page, FLASH_PAGE_SIZE) == 0) {
              return;
          }

          uint32_t offset = PICO_FLASH_SIZE_BYTES - FLASH_SECTOR_SIZE;
          if (flash_safe_execute(bareruby_attach_erase, &offset, UINT32_MAX) == 0) {
              flash_safe_execute(bareruby_attach_program, &offset, UINT32_MAX);
          }
      }

      static const char *bareruby_board_name(void) {
          if (bareruby_attaching) {
              return (const char *)bareruby_attached_page + BARERUBY_NAME_MARK_LENGTH;
          }
          const char *page = (const char *)BARERUBY_NAME_PAGE;
          if (memcmp(page, BARERUBY_NAME_MARK, BARERUBY_NAME_MARK_LENGTH) != 0) {
              return NULL;
          }
          return page + BARERUBY_NAME_MARK_LENGTH;
      }

      /* From here down this is pico-sdk's own descriptor set, which the build switched off
         to make room for this one. **The vendor and product ids are kept exactly**: the
         flasher tells an RP2040 from an RP2350 by the product id, and a board that renamed
         itself out of that table would be a board nothing could find. */
      #define USBD_VID (0x2E8A)
      #if PICO_RP2040
      #define USBD_PID (0x000a)
      #else
      #define USBD_PID (0x0009)
      #endif

      #define USBD_MANUFACTURER "Raspberry Pi"

      /* **What the board says it is, in four letters and its own name.** The mark is the
         protocol rather than the model: a host that has this board in a list wants to
         know which of its boards this is, and the model is already in the name a desk
         gave it. It used to say `BareRuby Debug Firm RP Pico1` as well, which is a true
         sentence that pushed the name out of every column it was printed in — and
         "debug" said nothing, because a board with no USB at all is the other build. */
      #define USBD_PRODUCT "BRDF"

      /* **A second interface that carries nothing, and is here to be described.** A host
         with no driver for an interface has nothing of its own to call it, so it falls
         back to the device's product string — which is this board's name. That is the
         only reason this one exists: on a Windows desk the board is otherwise called
         after the serial driver that claimed it, and every board of every kind reads the
         same. It is what the chip's own bootloader does, where an unclaimed PICOBOOT
         interface is why `RP2 Boot` appears beside the mass storage.

         **BRDF itself is not here.** It goes over the serial port, in the stream a
         program's output also goes over, marked out by a word. A program printing that
         word can answer for the board — which is a real hole, taken knowingly: the
         firmware this happens in is the debug build, on a desk, being written to by the
         person who wrote the program. */
      #define USBD_DESC_LEN (TUD_CONFIG_DESC_LEN + TUD_CDC_DESC_LEN + TUD_VENDOR_DESC_LEN)
      #define USBD_ITF_MAX (3)

      #define USBD_ITF_CDC (0)
      #define USBD_CDC_EP_CMD (0x81)
      #define USBD_CDC_EP_OUT (0x02)
      #define USBD_CDC_EP_IN (0x82)
      #define USBD_CDC_CMD_MAX_SIZE (8)
      #define USBD_CDC_IN_OUT_MAX_SIZE (64)

      /* The pipes of the interface above. Nothing is sent or received on them; TinyUSB has
         to be able to claim the interface for the configuration to be set at all, and a
         vendor interface is claimed by having endpoints. */
      #define USBD_ITF_BRDF (2)
      #define USBD_BRDF_EP_OUT (0x03)
      #define USBD_BRDF_EP_IN (0x83)
      #define USBD_BRDF_EP_SIZE (64)

      #define USBD_STR_LANGUAGE (0x00)
      #define USBD_STR_MANUF (0x01)
      #define USBD_STR_PRODUCT (0x02)
      #define USBD_STR_SERIAL (0x03)
      #define USBD_STR_CDC (0x04)

      /* Long enough for the visible product wrapped around the longest persisted name. */
      #define USBD_DESC_STR_MAX (64)

      static const tusb_desc_device_t usbd_desc_device = {
          .bLength = sizeof(tusb_desc_device_t),
          .bDescriptorType = TUSB_DESC_DEVICE,
          .bcdUSB = 0x0200,
          /* **A container, and this time it is one.** The three together are how a device
             says "what I am is written in my interfaces, and the associations tell you
             which of them go together" — which is exactly true of a board carrying a
             serial port and BRDF side by side. */
          .bDeviceClass = TUSB_CLASS_MISC,
          .bDeviceSubClass = MISC_SUBCLASS_COMMON,
          .bDeviceProtocol = MISC_PROTOCOL_IAD,
          .bMaxPacketSize0 = CFG_TUD_ENDPOINT0_SIZE,
          .idVendor = USBD_VID,
          .idProduct = USBD_PID,
          .bcdDevice = 0x0100,
          .iManufacturer = USBD_STR_MANUF,
          .iProduct = USBD_STR_PRODUCT,
          .iSerialNumber = USBD_STR_SERIAL,
          .bNumConfigurations = 1,
      };

      /* **BRDF's interface is given no name of its own, on purpose.** A host that has no
         driver for it falls back to the device's product string to describe it — which is
         this board's name, the one thing worth reading there. An interface string would
         stand in front of that and say something less useful. It is how the chip's own
         bootloader reads on a Windows desk, for the same reason. */
      static const uint8_t usbd_desc_cfg[USBD_DESC_LEN] = {
          TUD_CONFIG_DESCRIPTOR(1, USBD_ITF_MAX, USBD_STR_LANGUAGE, USBD_DESC_LEN, 0, 250),

          TUD_CDC_DESCRIPTOR(USBD_ITF_CDC, USBD_STR_CDC, USBD_CDC_EP_CMD,
              USBD_CDC_CMD_MAX_SIZE, USBD_CDC_EP_OUT, USBD_CDC_EP_IN, USBD_CDC_IN_OUT_MAX_SIZE),

          TUD_VENDOR_DESCRIPTOR(USBD_ITF_BRDF, 0, USBD_BRDF_EP_OUT, USBD_BRDF_EP_IN,
              USBD_BRDF_EP_SIZE),
      };

      /* In the order the indices above name them. The language, product, serial and CDC
         function are answered rather than listed because three of those contain the name
         this particular board carries. */
      static const char *const usbd_desc_str[] = {
          NULL,
          USBD_MANUFACTURER,
          NULL,
          NULL,
          NULL,
      };

      static char usbd_serial_str[PICO_UNIQUE_BOARD_ID_SIZE_BYTES * 2 + 1];
      static char usbd_product_str[USBD_DESC_STR_MAX];

      const uint8_t *tud_descriptor_device_cb(void) {
          return (const uint8_t *)&usbd_desc_device;
      }

      const uint8_t *tud_descriptor_configuration_cb(uint8_t index) {
          (void)index;
          return usbd_desc_cfg;
      }

      /* **The one string this file exists for.** A board that was attached answers with
         the name it was attached under; one that never was answers with the chip's unique
         id, which is what pico-sdk would have said. */
      static const char *bareruby_serial_string(void) {
          const char *named = bareruby_board_name();
          if (named != NULL) {
              return named;
          }
          if (usbd_serial_str[0] == 0) {
              pico_get_unique_board_id_string(usbd_serial_str, sizeof(usbd_serial_str));
          }
          return usbd_serial_str;
      }

      static const char *bareruby_product_string(void) {
          snprintf(usbd_product_str, sizeof(usbd_product_str), "%s %s",
                   USBD_PRODUCT, bareruby_serial_string());
          return usbd_product_str;
      }

      const uint16_t *tud_descriptor_string_cb(uint8_t index, uint16_t langid) {
          (void)langid;
          static uint16_t desc_str[USBD_DESC_STR_MAX];

          uint8_t len;
          if (index == USBD_STR_LANGUAGE) {
              desc_str[1] = 0x0409;
              len = 1;
          } else {
              if (index >= sizeof(usbd_desc_str) / sizeof(usbd_desc_str[0])) {
                  return NULL;
              }
              const char *str;
              if (index == USBD_STR_SERIAL) {
                  str = bareruby_serial_string();
              } else if (index == USBD_STR_PRODUCT || index == USBD_STR_CDC) {
                  str = bareruby_product_string();
              } else {
                  str = usbd_desc_str[index];
              }
              for (len = 0; len < USBD_DESC_STR_MAX - 1 && str[len]; ++len) {
                  desc_str[1 + len] = str[len];
              }
          }

          desc_str[0] = (uint16_t)((TUSB_DESC_STRING << 8) | (2 * len + 2));
          return desc_str;
      }
      #endif
    CPP

    # The resident updater is separate from USB identity: it listens for BRLOAD, stages
    # the image, replaces flash from RAM, and reboots. It reaches identity only once to
    # persist an attach-time name after USB has enumerated.
    RESIDENT_UPDATE = <<~CPP
      #if LIB_PICO_STDIO_USB

      #include <stdio.h>
      #include <stdlib.h>
      #include <string.h>

      #include "hardware/flash.h"
      #include "hardware/structs/psm.h"
      #include "hardware/structs/watchdog.h"
      #include "hardware/sync.h"
      #include "hardware/watchdog.h"
      #include "pico/flash.h"
      #include "pico/multicore.h"
      #include "pico/stdio_usb.h"
      #include "pico/stdlib.h"

      extern "C" void bareruby_persist_attached_name(void);

      /* ---- Taking a new program without going through the bootloader ----------------
         **A board in BOOTSEL has no name.** The name lives in a page this board's own
         firmware reads and hands to USB, and the bootloader is the chip's ROM, which has
         never heard of it. So every trip through BOOTSEL loses the one thing that says
         which board this is — and a run that failed there left boards sitting in it,
         nameless, for the next run to fail on in turn.

         The way out is not to go. A board already running can be handed its next program
         over the wire it is already talking on.

         **Core 1 listens, because core 0 never comes back.** A BareRuby program is a loop
         that does not return, so there is nowhere in it to ask whether a new one has
         arrived. The other core has nothing else to do.

         **What arrives is put somewhere else first.** The program cannot be written
         straight into the place it is running from, so it is collected in a staging half
         of the flash — reachable because writing there is writing somewhere this code is
         not — and moved into place at the end, when there is nothing left to receive.

         **The move runs from RAM.** Programming flash stops the chip reading flash, so a
         loop that did it while itself living in flash would be sawing the branch it sits
         on. `__no_inline_not_in_flash_func` keeps the whole loop in RAM; between writes
         the chip can read flash again, which is what lets the same loop pick the next page
         up out of staging. Interrupts are off for the whole of it, since every handler is
         in the flash being replaced. */
      #define BARERUBY_STAGING (PICO_FLASH_SIZE_BYTES / 2)
      #define BARERUBY_TAKE "BRLOAD"
      #define BARERUBY_TAKE_LENGTH 6

      static uint32_t bareruby_taking;
      static uint8_t bareruby_page[FLASH_PAGE_SIZE];

      static void bareruby_program_page(void *offset) {
          flash_range_program(*(uint32_t *)offset, bareruby_page, FLASH_PAGE_SIZE);
      }

      static void bareruby_erase_sector(void *offset) {
          flash_range_erase(*(uint32_t *)offset, FLASH_SECTOR_SIZE);
      }

      /* **Nothing in flash may be called once the erasing starts** — including the things
         nobody writes down as calls. The first version of this copied each page with
         `memcpy`, which lives in the library, which lives in the flash being replaced: the
         moment the first sector went, so did the copier's own memcpy, and what was left on
         the board was half an image that could not answer for itself over USB. So the copy
         is spelled out a byte at a time, inside the one function that RAM holds.

         The pages are read between writes rather than during them, which is what makes
         reading them possible at all: programming flash stops the chip reading flash, and
         hands it back when it returns. */
      static void __no_inline_not_in_flash_func(bareruby_move_and_reboot)(uint32_t length) {
          uint32_t sectors = (length + FLASH_SECTOR_SIZE - 1) / FLASH_SECTOR_SIZE;
          uint32_t written = 0;
          uint32_t index;
          uint32_t page;
          uint32_t offset;
          for (index = 0; index < sectors; index++) {
              flash_range_erase(index * FLASH_SECTOR_SIZE, FLASH_SECTOR_SIZE);
              for (page = 0; page < FLASH_SECTOR_SIZE; page += FLASH_PAGE_SIZE) {
                  offset = index * FLASH_SECTOR_SIZE + page;
                  if (offset >= length) {
                      break;
                  }
                  const uint8_t *from = (const uint8_t *)(XIP_BASE + BARERUBY_STAGING + offset);
                  uint32_t byte;
                  for (byte = 0; byte < FLASH_PAGE_SIZE; byte++) {
                      bareruby_page[byte] = from[byte];
                  }
                  flash_range_program(offset, bareruby_page, FLASH_PAGE_SIZE);
                  written += FLASH_PAGE_SIZE;
              }
          }
          (void)written;

          /* This function cannot return into the image it just replaced, nor call the
             SDK's watchdog_reboot(), which lived in that image too. Trigger the same
             ordinary flash reboot directly from the RAM-resident tail. */
          hw_clear_bits(&watchdog_hw->ctrl, WATCHDOG_CTRL_ENABLE_BITS);
          watchdog_hw->scratch[4] = 0;
          hw_set_bits(&psm_hw->wdsel,
              PSM_WDSEL_BITS & ~(PSM_WDSEL_ROSC_BITS | PSM_WDSEL_XOSC_BITS));
          hw_clear_bits(&watchdog_hw->ctrl,
              WATCHDOG_CTRL_PAUSE_DBG0_BITS |
              WATCHDOG_CTRL_PAUSE_DBG1_BITS |
              WATCHDOG_CTRL_PAUSE_JTAG_BITS);
          hw_set_bits(&watchdog_hw->ctrl, WATCHDOG_CTRL_TRIGGER_BITS);
          for (;;) {
              __asm volatile ("nop");
          }
      }

      static void bareruby_take(uint32_t length) {
          uint32_t offset = 0;
          uint32_t filled = 0;
          uint32_t sector;
          int one;
          for (sector = 0; sector < length + FLASH_SECTOR_SIZE; sector += FLASH_SECTOR_SIZE) {
              uint32_t at = BARERUBY_STAGING + sector;
              flash_safe_execute(bareruby_erase_sector, &at, UINT32_MAX);
          }
          while (offset < length) {
              one = getchar_timeout_us(5000000);
              if (one == PICO_ERROR_TIMEOUT) {
                  return;
              }
              bareruby_page[filled++] = (uint8_t)one;
              offset++;
              if (filled == FLASH_PAGE_SIZE || offset == length) {
                  uint32_t at = BARERUBY_STAGING + offset - filled;
                  while (filled < FLASH_PAGE_SIZE) {
                      bareruby_page[filled++] = 0xff;
                  }
                  flash_safe_execute(bareruby_program_page, &at, UINT32_MAX);
                  filled = 0;
              }
          }
          /* Said before the move, because after it this program is gone. */
          printf("BRDONE\\n");
          sleep_ms(200);
          /* **Parking the other core comes first, and interrupts go down after it.** The
             parking is a conversation between the cores and it is carried by interrupts,
             so a core that has already silenced its own has nothing left to hold that
             conversation with: it asks, is never answered, and waits there. The board
             goes on running the program it had, which is how this first showed itself —
             the whole image arrived, the board said so, and then nothing happened. */
          multicore_lockout_start_blocking();
          save_and_disable_interrupts();
          bareruby_move_and_reboot(length);
      }

      /* `BRLOAD` and eight hex digits of length. Anything else on this channel is a
         program's own output and is left alone. */
      static void bareruby_watch(void) {
          /* Core 0 was registered as the flash lockout victim before this core started.
             Persisting here therefore takes the same proven path as resident deploy:
             core 1 performs the flash operation while core 0 keeps USB alive. Give the
             first descriptor exchange time to finish before briefly locking it out. */
          sleep_ms(1000);
          bareruby_persist_attached_name();

          char asked[BARERUBY_TAKE_LENGTH + 9];
          uint32_t held = 0;
          int one;
          for (;;) {
              one = getchar_timeout_us(500000);
              if (one == PICO_ERROR_TIMEOUT) {
                  continue;
              }
              asked[held++] = (char)one;
              if (held < BARERUBY_TAKE_LENGTH) {
                  continue;
              }
              if (memcmp(asked, BARERUBY_TAKE, BARERUBY_TAKE_LENGTH) != 0) {
                  held = 0;
                  continue;
              }
              if (held < sizeof(asked) - 1) {
                  continue;
              }
              asked[sizeof(asked) - 1] = '\\0';
              bareruby_taking = (uint32_t)strtoul(asked + BARERUBY_TAKE_LENGTH, NULL, 16);
              held = 0;
              bareruby_take(bareruby_taking);
          }
      }

      extern "C" void bareruby_agent_start(void) {
          flash_safe_execute_core_init();
          multicore_launch_core1(bareruby_watch);
      }
      #endif
    CPP

    # Every Raspberry Pi Pico board shares one binding: the peripherals are reached
    # through pico-sdk, which spells them the same way whichever chip is underneath.
    # Only the board name handed to the SDK tells the two apart.
    PWM_FILE = "bareruby_binding_pwm_pico.cpp"
    ADC_FILE = "bareruby_binding_adc_pico.cpp"
    UART_FILE = "bareruby_binding_uart_pico.cpp"
    GPIO_FILE = "bareruby_binding_gpio_pico.cpp"
    PERIPHERAL_FILE = "bareruby_binding_pico.cpp"
    UART_RECEIVE_FILE = "bareruby_binding_uart_receive_pico.cpp"
    UART_INTERRUPT_FILE = "bareruby_binding_uart_interrupt_pico.cpp"
    I2C_FILE = "bareruby_binding_i2c_pico.cpp"
    I2C_READ_FILE = "bareruby_binding_i2c_read_pico.cpp"
    IDENTITY_FILE = "bareruby_binding_identity_pico.cpp"
    RESIDENT_UPDATE_FILE = "bareruby_binding_resident_update_pico.cpp"

    # A board whose indicator is on a pin of the microcontroller. Which pin is the
    # board's answer, not this file's: pico-sdk's board header defines
    # PICO_DEFAULT_LED_PIN, so a board that puts its LED elsewhere needs no change here.
    ONBOARD_LED_PIN = <<~CPP
      #include "bareruby_binding.h"

      #include "hardware/gpio.h"

      void bareruby_onboard_led_init(bareruby_onboard_led_t *self) {
          self->state = 0;
          gpio_init(PICO_DEFAULT_LED_PIN);
          gpio_set_dir(PICO_DEFAULT_LED_PIN, GPIO_OUT);
      }

      void bareruby_onboard_led_write(bareruby_onboard_led_t *self, int32_t value) {
          self->state = (value != 0) ? 1 : 0;
          gpio_put(PICO_DEFAULT_LED_PIN, self->state != 0);
      }

      void bareruby_onboard_led_on(bareruby_onboard_led_t *self) {
          bareruby_onboard_led_write(self, 1);
      }

      void bareruby_onboard_led_off(bareruby_onboard_led_t *self) {
          bareruby_onboard_led_write(self, 0);
      }
    CPP

    # A wireless board's indicator hangs off the radio, not off a pin, so reaching it
    # means bringing the CYW43 up first — the chip runs firmware that the host uploads,
    # which is what this costs. GP25, where the plain board's LED sits, is the radio's
    # select line on this one; writing it here would fight the driver rather than blink.
    ONBOARD_LED_RADIO = <<~CPP
      #include "bareruby_binding.h"

      #include "pico/cyw43_arch.h"

      void bareruby_onboard_led_init(bareruby_onboard_led_t *self) {
          self->state = 0;
          cyw43_arch_init();
      }

      void bareruby_onboard_led_write(bareruby_onboard_led_t *self, int32_t value) {
          self->state = (value != 0) ? 1 : 0;
          cyw43_arch_gpio_put(CYW43_WL_GPIO_LED_PIN, self->state != 0);
      }

      void bareruby_onboard_led_on(bareruby_onboard_led_t *self) {
          bareruby_onboard_led_write(self, 1);
      }

      void bareruby_onboard_led_off(bareruby_onboard_led_t *self) {
          bareruby_onboard_led_write(self, 0);
      }
    CPP

    ONBOARD_LED_PIN_FILE = "bareruby_binding_onboard_led_pico_sdk_pin.cpp"
    ONBOARD_LED_RADIO_FILE = "bareruby_binding_onboard_led_pico_sdk_radio.cpp"

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
      IDENTITY_FILE => IDENTITY,
      RESIDENT_UPDATE_FILE => RESIDENT_UPDATE,
      ONBOARD_LED_PIN_FILE => ONBOARD_LED_PIN,
      ONBOARD_LED_RADIO_FILE => ONBOARD_LED_RADIO
    }.freeze

    # Every binding answers the same questions with the same names, so a build picks one
    # of these modules and asks it the same things.
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

    # Its name is not something a program asks for, so nothing in the Ruby reaches this
    # unit and no peripheral key names it. **What it answers is asked by the host**, over
    # USB, before the program has run a line.
    ALWAYS = [PERIPHERAL_FILE, IDENTITY_FILE, RESIDENT_UPDATE_FILE].freeze

    # Reaching the radio's indicator is a driver and a firmware blob rather than a
    # register write, so the way that does it carries what it needs linked.
    RADIO_LIBRARY = "pico_cyw43_arch_none"


    # What a machine takes is not worked out here. Each machine this binding reaches
    # writes its own answer as a method, in machine/ beside this file, and this only hands
    # the question over. A machine it cannot reach has no answer rather than a wrong one.
    MACHINES = {}

    def self.machine(machine) = MACHINES.fetch(machine.key)

    # pico-sdk hands the program the whole executable, so the entry point is this side's
    # to write and the translation unit that carries it is named for it.
    PROGRAM_FILE = "main.cpp"

    def self.key = :pico_sdk

    def self.toolchain = PicoSdkToolchain

    # What this binding reaches for that it does not carry. A binding without one is a
    # binding that needs nothing fetched, which is an answer rather than an omission.
    def self.tools = PicoSdkTools

    def self.flash = PicoSdkFlash

    # What `bareruby target attach` reaches. A binding whose boards carry no name of their
    # own does not declare this, and the command says so rather than failing — the same
    # shape as `init` for a family that keeps no configuration.
    def self.board = PicoSdkBoard

    def self.build = PicoSdkBuild
  end
end

# One machine to a file, so that teaching this binding a new machine is adding a file.
Dir.children(File.expand_path("machine", __dir__)).sort.grep(/\.rb\z/).each do |entry|
  require_relative "machine/#{entry}"
end
