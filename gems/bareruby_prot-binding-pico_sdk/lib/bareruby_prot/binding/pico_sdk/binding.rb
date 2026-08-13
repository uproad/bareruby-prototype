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

      /* The uart_interrupt unit overrides this when a program says on_line; otherwise
         sleep drains nothing and pays one empty call per millisecond. */
      extern "C" __attribute__((weak)) void bareruby_uart_interrupt_drain(void) {}

      void bareruby_machine_delay_us(int32_t microseconds) {
          sleep_us((uint64_t)microseconds);
      }

      void bareruby_sleep_ms(int32_t milliseconds) {
          absolute_time_t deadline = make_timeout_time_ms((uint32_t)(milliseconds > 0 ? milliseconds : 0));
          for (;;) {
              bareruby_uart_interrupt_drain();
              if (time_reached(deadline)) {
                  break;
              }
              sleep_ms(1);
          }
      }

      void bareruby_sleep(int32_t seconds) {
          bareruby_sleep_ms(seconds > 0 ? seconds * 1000 : 0);
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

      int32_t bareruby_ticks_ms(void) {
          return (int32_t)to_ms_since_boot(get_absolute_time());
      }
    CPP

    UART_RECEIVE = <<~CPP
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

    # The receive interrupt. The ISR does one thing — move what the FIFO holds into a
    # 256-byte ring — and every policy (LF/CRLF framing, the 255-byte cap, the overlong
    # discard, the handler itself) runs in thread mode when sleep drains the ring. One
    # producer, one consumer, single-byte indices that wrap by uint8_t overflow: no
    # critical section is needed on a Cortex-M0+ or M33.
    UART_INTERRUPT = <<~CPP
      #include "bareruby_binding.h"

      #include "hardware/irq.h"
      #include "hardware/uart.h"

      typedef struct {
          volatile uint8_t data[256];   /* the 256 bytes on_line costs; ISR writes, drain reads */
          volatile uint8_t head;        /* ISR-owned */
          volatile uint8_t tail;        /* drain-owned */
          char line[256];               /* the view a handler is handed points here */
          int32_t line_length;
          bool discarding;              /* an overlong line, thrown away to the next LF */
          bareruby_uart_line_handler_t handler;
          uart_inst_t *port;
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

      static void bareruby_uart_interrupt_isr(void) {
          uart_inst_t *port = bareruby_uart_interrupt.port;
          while (uart_is_readable(port)) {
              /* The FIFO's data register carries the error flags beside the byte; a
                 byte whose parity failed is discarded, as Arduino's core does. */
              uint32_t entry = uart_get_hw(port)->dr;
              if ((entry & UART_UARTDR_PE_BITS) == 0u) {
                  bareruby_uart_interrupt_push((uint8_t)(entry & 0xFFu));
              }
          }
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
          if (bareruby_uart_interrupt.handler == NULL) {
              return;
          }
          while (bareruby_uart_interrupt.tail != bareruby_uart_interrupt.head) {
              uint8_t byte = bareruby_uart_interrupt.data[bareruby_uart_interrupt.tail];
              bareruby_uart_interrupt.tail = (uint8_t)(bareruby_uart_interrupt.tail + 1u);
              bareruby_uart_interrupt_line_byte(byte);
          }
      }

      /* The first touch of the receive side — a registration or a buffered read — is
         what arms the interrupt and so what buys the ring. */
      static void bareruby_uart_interrupt_attach(bareruby_uart_t *self) {
          if (bareruby_uart_interrupt.port != NULL) {
              return;
          }
          uart_inst_t *port = (self->id == 0) ? uart0 : uart1;
          uint irq = (self->id == 0) ? UART0_IRQ : UART1_IRQ;
          bareruby_uart_interrupt.port = port;   /* published before the IRQ can fire */
          irq_set_exclusive_handler(irq, bareruby_uart_interrupt_isr);
          irq_set_enabled(irq, true);
          /* RX on, TX off. This also arms the receive-timeout interrupt, so a line
             shorter than the FIFO watermark still arrives promptly. */
          uart_set_irq_enables(port, true, false);
      }

      void bareruby_uart_on_line(bareruby_uart_t *self, bareruby_uart_line_handler_t handler) {
          bareruby_uart_interrupt.handler = handler;
          bareruby_uart_interrupt_attach(self);
      }

      int32_t bareruby_uart_read_byte(bareruby_uart_t *self) {
          bareruby_uart_interrupt_attach(self);
          if (bareruby_uart_interrupt.tail == bareruby_uart_interrupt.head) {
              return -1;
          }
          uint8_t byte = bareruby_uart_interrupt.data[bareruby_uart_interrupt.tail];
          bareruby_uart_interrupt.tail = (uint8_t)(bareruby_uart_interrupt.tail + 1u);
          return (int32_t)byte;
      }

      int32_t bareruby_uart_peek(bareruby_uart_t *self) {
          bareruby_uart_interrupt_attach(self);
          if (bareruby_uart_interrupt.tail == bareruby_uart_interrupt.head) {
              return -1;
          }
          return (int32_t)bareruby_uart_interrupt.data[bareruby_uart_interrupt.tail];
      }

      /* The strong definition; the polling one in the uart unit is weak. */
      int32_t bareruby_uart_bytes_available(bareruby_uart_t *self) {
          bareruby_uart_interrupt_attach(self);
          return (int32_t)(uint8_t)(bareruby_uart_interrupt.head - bareruby_uart_interrupt.tail);
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
    IDENTITY = <<~CPP
      #if LIB_PICO_STDIO_USB

      #include <stdio.h>
      #include <stdlib.h>
      #include <string.h>

      #include "hardware/flash.h"
      #include "hardware/sync.h"
      #include "hardware/watchdog.h"
      #include "pico/flash.h"
      #include "pico/multicore.h"
      #include "pico/stdio_usb.h"
      #include "pico/stdlib.h"
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

      static const char *bareruby_board_name(void) {
          const char *page = (const char *)BARERUBY_NAME_PAGE;
          if (memcmp(page, BARERUBY_NAME_MARK, BARERUBY_NAME_MARK_LENGTH) != 0) {
              return NULL;
          }
          return page + BARERUBY_NAME_MARK_LENGTH;
      }

      /* From here down this is pico-sdk's own descriptor set, which the build switched off
         to make room for this one. **The vendor and product ids are kept exactly**: the
         flasher tells an RP2040 from an RP2350 by the product id, and a board that renamed
         itself out of that table would be a board nothing could find. What changes is one
         string. */
      #define USBD_VID (0x2E8A)
      #if PICO_RP2040
      #define USBD_PID (0x000a)
      #else
      #define USBD_PID (0x0009)
      #endif

      #define USBD_MANUFACTURER "Raspberry Pi"
      #define USBD_PRODUCT "Pico"

      #if !PICO_ENABLE_USB_RESET_VIA_VENDOR_INTERFACE
      #define USBD_DESC_LEN (TUD_CONFIG_DESC_LEN + TUD_CDC_DESC_LEN)
      #define USBD_ITF_MAX (2)
      #else
      #define USBD_DESC_LEN (TUD_CONFIG_DESC_LEN + TUD_CDC_DESC_LEN + TUD_RPI_RESET_DESC_LEN)
      #define USBD_ITF_RPI_RESET (2)
      #define USBD_ITF_MAX (3)
      #endif

      #define USBD_ITF_CDC (0)
      #define USBD_CDC_EP_CMD (0x81)
      #define USBD_CDC_EP_OUT (0x02)
      #define USBD_CDC_EP_IN (0x82)
      #define USBD_CDC_CMD_MAX_SIZE (8)
      #define USBD_CDC_IN_OUT_MAX_SIZE (64)

      #define USBD_STR_LANGUAGE (0x00)
      #define USBD_STR_MANUF (0x01)
      #define USBD_STR_PRODUCT (0x02)
      #define USBD_STR_SERIAL (0x03)
      #define USBD_STR_CDC (0x04)
      #define USBD_STR_RPI_RESET (0x05)

      /* Long enough for a name a person would type. pico-sdk allows 127 and offers 20,
         which is shorter than some of the names already in a target record. */
      #define USBD_DESC_STR_MAX (40)

      static const tusb_desc_device_t usbd_desc_device = {
          .bLength = sizeof(tusb_desc_device_t),
          .bDescriptorType = TUSB_DESC_DEVICE,
      #if PICO_ENABLE_USB_RESET_VIA_VENDOR_INTERFACE && PICO_USB_RESET_SUPPORT_MS_OS_20_DESCRIPTOR
          .bcdUSB = 0x0210,
      #else
          .bcdUSB = 0x0200,
      #endif
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

      static const uint8_t usbd_desc_cfg[USBD_DESC_LEN] = {
          TUD_CONFIG_DESCRIPTOR(1, USBD_ITF_MAX, USBD_STR_LANGUAGE, USBD_DESC_LEN, 0, 250),

          TUD_CDC_DESCRIPTOR(USBD_ITF_CDC, USBD_STR_CDC, USBD_CDC_EP_CMD,
              USBD_CDC_CMD_MAX_SIZE, USBD_CDC_EP_OUT, USBD_CDC_EP_IN, USBD_CDC_IN_OUT_MAX_SIZE),

      #if PICO_ENABLE_USB_RESET_VIA_VENDOR_INTERFACE
          TUD_RPI_RESET_DESCRIPTOR(USBD_ITF_RPI_RESET, USBD_STR_RPI_RESET),
      #endif
      };

      /* In the order the indices above name them. Two are answered rather than listed:
         index 0 is the language, and the serial is whatever the board is called. */
      static const char *const usbd_desc_str[] = {
          NULL,
          USBD_MANUFACTURER,
          USBD_PRODUCT,
          NULL,
          "Board CDC",
      #if PICO_ENABLE_USB_RESET_VIA_VENDOR_INTERFACE
          "Reset",
      #endif
      };

      static char usbd_serial_str[PICO_UNIQUE_BOARD_ID_SIZE_BYTES * 2 + 1];

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
              const char *str =
                  (index == USBD_STR_SERIAL) ? bareruby_serial_string() : usbd_desc_str[index];
              for (len = 0; len < USBD_DESC_STR_MAX - 1 && str[len]; ++len) {
                  desc_str[1 + len] = str[len];
              }
          }

          desc_str[0] = (uint16_t)((TUSB_DESC_STRING << 8) | (2 * len + 2));
          return desc_str;
      }

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
         on. `__not_in_flash_func` puts the loop in RAM; between writes the chip can read
         flash again, which is what lets the same loop pick the next page up out of
         staging. Interrupts are off for the whole of it, since every handler is in the
         flash being replaced. */
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

      /* Nothing here may be called once the erasing starts, so the whole of the move is
         one function and the pages it reads are read between writes rather than during
         them. */
      static void __not_in_flash_func(bareruby_move)(uint32_t length) {
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
                  memcpy(bareruby_page, (const uint8_t *)(XIP_BASE + BARERUBY_STAGING + offset),
                         FLASH_PAGE_SIZE);
                  flash_range_program(offset, bareruby_page, FLASH_PAGE_SIZE);
                  written += FLASH_PAGE_SIZE;
              }
          }
          (void)written;
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
          save_and_disable_interrupts();
          multicore_lockout_start_blocking();
          bareruby_move(length);
          watchdog_reboot(0, 0, 0);
          for (;;) {
              tight_loop_contents();
          }
      }

      /* `BRLOAD` and eight hex digits of length. Anything else on this channel is a
         program's own output and is left alone. */
      static void bareruby_watch(void) {
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
    ALWAYS = [PERIPHERAL_FILE, IDENTITY_FILE].freeze

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
