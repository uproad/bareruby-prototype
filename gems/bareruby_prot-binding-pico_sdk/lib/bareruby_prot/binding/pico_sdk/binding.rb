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

      void bareruby_startup(void) {
          stdio_init_all();
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

    # Every Raspberry Pi Pico board shares one binding: the peripherals are reached
    # through pico-sdk, which spells them the same way whichever chip is underneath.
    # Only the board name handed to the SDK tells the two apart.
    PWM_FILE = "bareruby_binding_pwm_pico.cpp"
    ADC_FILE = "bareruby_binding_adc_pico.cpp"
    UART_FILE = "bareruby_binding_uart_pico.cpp"
    GPIO_FILE = "bareruby_binding_gpio_pico.cpp"
    PERIPHERAL_FILE = "bareruby_binding_pico.cpp"
    UART_RECEIVE_FILE = "bareruby_binding_uart_receive_pico.cpp"
    I2C_FILE = "bareruby_binding_i2c_pico.cpp"
    I2C_READ_FILE = "bareruby_binding_i2c_read_pico.cpp"

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
      I2C_FILE => I2C,
      I2C_READ_FILE => I2C_READ,
      ONBOARD_LED_PIN_FILE => ONBOARD_LED_PIN,
      ONBOARD_LED_RADIO_FILE => ONBOARD_LED_RADIO
    }.freeze

    # Every binding answers the same questions with the same names, so a build picks one
    # of these modules and asks it the same things.
    # What a peripheral asks for by key, this binding answers with a file. The key is the
    # peripheral's word and the file is this side's, so neither has to know the other.
    UNITS = { onboard_led: :onboard_led_file, gpio: GPIO_FILE, adc: ADC_FILE, uart: UART_FILE, uart_receive: UART_RECEIVE_FILE, pwm: PWM_FILE, i2c: I2C_FILE, i2c_read: I2C_READ_FILE }.freeze

    # A unit is usually one file. **Some are the machine's answer instead** — an
    # indicator is reached through a pin on one board and through a radio on another, so
    # the key resolves to a question rather than a name, and the cell beside this file
    # answers it.
    def self.unit(key, machine)
      found = UNITS.fetch(key)
      found.is_a?(Symbol) ? machine(machine).public_send(found) : found
    end

    ALWAYS = [PERIPHERAL_FILE].freeze

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

    def self.flash = PicoSdkFlash

    def self.build = PicoSdkBuild
  end
end

# One machine to a file, so that teaching this binding a new machine is adding a file.
Dir.children(File.expand_path("machine", __dir__)).sort.grep(/\.rb\z/).each do |entry|
  require_relative "machine/#{entry}"
end
