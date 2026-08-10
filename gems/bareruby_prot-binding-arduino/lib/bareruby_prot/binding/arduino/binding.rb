# frozen_string_literal: true

module BareRubyProt
  module ArduinoBinding
    # The console every program gets. A board reached through this core has a USB-serial
    # bridge of its own, so there is always somewhere for output to arrive and nothing to
    # turn on to get it — which is why this build has a stdout channel unconditionally
    # where a Pico only has one in a debug firmware.
    CONSOLE_BAUD = 115_200

    # GPIO in its own translation unit. **A peripheral that can be uninstalled cannot
    # share a file with one that cannot** — the declarations go with the gem, and an
    # implementation left behind would have nothing to implement against.
    PWM = <<~CPP
      #include "bareruby_binding.h"
      #include <Arduino.h>
      #include <stdarg.h>
      #include <stdio.h>
      #include <string.h>

      void bareruby_pwm_init(bareruby_pwm_t *self, int32_t pin, int32_t frequency, int32_t duty) {
          self->pin = pin;
          self->slice = 0;
          self->frequency = frequency;
          pinMode((uint8_t)pin, OUTPUT);
          bareruby_pwm_duty(self, duty);
      }

      void bareruby_pwm_frequency(bareruby_pwm_t *self, int32_t frequency) {
          self->frequency = frequency;
      }

      void bareruby_pwm_period_us(bareruby_pwm_t *self, int32_t period_us) {
          self->frequency = period_us > 0 ? (int32_t)(1000000 / period_us) : 0;
      }

      void bareruby_pwm_duty(bareruby_pwm_t *self, int32_t duty) {
          analogWrite((uint8_t)self->pin, (int)(255 * duty / 100));
      }

      void bareruby_pwm_pulse_width_us(bareruby_pwm_t *self, int32_t pulse_width_us) {
          int32_t period_us = self->frequency > 0 ? (int32_t)(1000000 / self->frequency) : 0;
          analogWrite(
              (uint8_t)self->pin,
              period_us > 0 ? (int)(255 * pulse_width_us / period_us) : 0);
      }
    CPP

    ADC = <<~CPP
      #include "bareruby_binding.h"
      #include <Arduino.h>
      #include <stdarg.h>
      #include <stdio.h>
      #include <string.h>

      /* The converter here is 10 bits against a 5 V reference, where a Pico's is 12 bits
         against 3.3 V, and the channel is the analog input's own number rather than a
         pin's distance from the first of them. read answers volts either way, which is
         what keeps a program that reads a voltage from carrying the board's numbers. */
      void bareruby_adc_init(bareruby_adc_t *self, int32_t pin) {
          self->pin = pin;
          self->channel = pin;
      }

      int32_t bareruby_adc_read_raw(bareruby_adc_t *self) {
          return (int32_t)analogRead((uint8_t)self->channel);
      }

      int32_t bareruby_adc_read(bareruby_adc_t *self) {
          int64_t raw = (int64_t)bareruby_adc_read_raw(self);
          return (int32_t)((raw * 5000 * 65536) / (1023 * 1000));
      }
    CPP

    UART = <<~CPP
      #include "bareruby_binding.h"
      #include <Arduino.h>
      #include <stdarg.h>
      #include <stdio.h>
      #include <string.h>

      /* This board carries four of them. Serial is the one on the USB bridge, which is
         why it is also the console, and 1 through 3 are the pin headers. */
      static HardwareSerial *bareruby_uart_port(const bareruby_uart_t *self) {
          switch (self->id) {
          case 1: return &Serial1;
          case 2: return &Serial2;
          case 3: return &Serial3;
          default: return &Serial;
          }
      }

      /* The core spells the whole frame as one byte, and the constants are laid out so
         that the three fields are separate bits: data bits in 2..1, stop bits in 3,
         parity in 5..4. Building the byte beats a table of thirty-six names. */
      static uint8_t bareruby_uart_configuration(
          int32_t data_bits, int32_t stop_bits, int32_t parity) {
          uint8_t configuration = (uint8_t)((data_bits - 5) << 1);
          if (stop_bits == 2) {
              configuration |= 0x08;
          }
          if (parity == 1) {
              configuration |= 0x20;
          } else if (parity == 2) {
              configuration |= 0x30;
          }
          return configuration;
      }

      void bareruby_uart_init(
          bareruby_uart_t *self, int32_t id, int32_t baud,
          int32_t data_bits, int32_t stop_bits, int32_t parity) {
          self->id = id;
          self->baud = baud;
          self->data_bits = data_bits;
          self->stop_bits = stop_bits;
          self->parity = parity;
          bareruby_uart_port(self)->begin(
              (unsigned long)baud, bareruby_uart_configuration(data_bits, stop_bits, parity));
      }

      int32_t bareruby_uart_write(bareruby_uart_t *self, const char *value) {
          size_t length = strlen(value);
          bareruby_uart_port(self)->write((const uint8_t *)value, length);
          return (int32_t)length;
      }

      void bareruby_uart_puts(bareruby_uart_t *self, const char *value) {
          (void)bareruby_uart_write(self, value);
          bareruby_uart_port(self)->write((uint8_t)'\\n');
      }

      void bareruby_uart_printf(bareruby_uart_t *self, const char *format, ...) {
          char payload[128];
          va_list arguments;
          va_start(arguments, format);
          vsnprintf(payload, sizeof(payload), format, arguments);
          va_end(arguments);
          (void)bareruby_uart_write(self, payload);
      }

      /* Weak for the same shape the other bindings have, though HardwareSerial's own
         count is already the buffered answer; the uart_interrupt unit's override only
         adds the arming touch. */
      __attribute__((weak)) int32_t bareruby_uart_bytes_available(bareruby_uart_t *self) {
          return (int32_t)bareruby_uart_port(self)->available();
      }

      /* availableForWrite reports the room left in the core's send ring, so what is still
         owed is the ring's size less that room, plus the frame in the shift register --
         which the core does not expose, so it is not counted. */
      int32_t bareruby_uart_bytes_to_write(bareruby_uart_t *self) {
          return (int32_t)(SERIAL_TX_BUFFER_SIZE - 1 - bareruby_uart_port(self)->availableForWrite());
      }

      /* **The core offers no break at all.** An AVR sends one by taking the pin back from
         the transmitter and holding it low, so that is what this does: drain, release the
         port, drive the pin, and start it again from what the program asked for -- which
         is the one place the frame kept in the struct is read back. */
      static uint8_t bareruby_uart_transmit_pin(const bareruby_uart_t *self) {
          switch (self->id) {
          case 1: return 18;
          case 2: return 16;
          case 3: return 14;
          default: return 1;
          }
      }

      void bareruby_uart_send_break(bareruby_uart_t *self, int32_t milliseconds) {
          HardwareSerial *port = bareruby_uart_port(self);
          uint8_t pin = bareruby_uart_transmit_pin(self);
          port->flush();
          port->end();
          pinMode(pin, OUTPUT);
          digitalWrite(pin, LOW);
          delay((unsigned long)(milliseconds > 0 ? milliseconds : 0));
          digitalWrite(pin, HIGH);
          port->begin((unsigned long)self->baud,
                      bareruby_uart_configuration(self->data_bits, self->stop_bits, self->parity));
      }

      bool bareruby_uart_can_read_line(bareruby_uart_t *self) {
          return bareruby_uart_port(self)->available() > 0;
      }

      void bareruby_uart_flush(bareruby_uart_t *self) {
          bareruby_uart_port(self)->flush();
      }

      void bareruby_uart_clear_rx_buffer(bareruby_uart_t *self) {
          while (bareruby_uart_port(self)->available() > 0) {
              (void)bareruby_uart_port(self)->read();
          }
      }

      void bareruby_uart_clear_tx_buffer(bareruby_uart_t *self) {
          bareruby_uart_port(self)->flush();
      }
    CPP

    GPIO = <<~CPP
      #include "bareruby_binding.h"
      #include <Arduino.h>
      #include <stdarg.h>
      #include <stdio.h>
      #include <string.h>

      static bareruby_interrupt_handler_t bareruby_gpio_interrupt_handler;

      static void bareruby_gpio_interrupt_trampoline(void) {
          bareruby_gpio_interrupt_handler();
      }

      /* This chip has pull-ups and no pull-downs, so a pin asked for one is left plain
         rather than given the other. What a pin can do is the chip's answer and not the
         program's, which is the same reason a pin with no converter channel is passed
         through as written. */
      void bareruby_gpio_init(bareruby_gpio_t *self, int32_t pin, int32_t params) {
          self->pin = pin;
          self->params = params;
          if (params & 2) {
              pinMode((uint8_t)pin, OUTPUT);
          } else if (params & 8) {
              pinMode((uint8_t)pin, INPUT_PULLUP);
          } else {
              pinMode((uint8_t)pin, INPUT);
          }
      }

      void bareruby_gpio_write(bareruby_gpio_t *self, int32_t value) {
          digitalWrite((uint8_t)self->pin, value != 0 ? HIGH : LOW);
      }

      int32_t bareruby_gpio_read(bareruby_gpio_t *self) {
          return digitalRead((uint8_t)self->pin) == HIGH ? 1 : 0;
      }

      bool bareruby_gpio_high(bareruby_gpio_t *self) {
          return bareruby_gpio_read(self) != 0;
      }

      bool bareruby_gpio_low(bareruby_gpio_t *self) {
          return bareruby_gpio_read(self) == 0;
      }

      void bareruby_gpio_on_interrupt(
          bareruby_gpio_t *self, int32_t events, bareruby_interrupt_handler_t handler) {
          bareruby_gpio_interrupt_handler = handler;
          attachInterrupt(
              digitalPinToInterrupt((uint8_t)self->pin), bareruby_gpio_interrupt_trampoline,
              (events & 4) ? FALLING : RISING);
      }

      /* The core's PWM is a duty cycle and nothing else: analogWrite picks its own
         frequency from the timer the pin sits on, and offers no way to say another. So a
         requested frequency is remembered rather than obeyed, and a pulse width is turned
         into the duty it would be at the frequency that was asked for — which is right
         only if the core happened to choose that one. Reaching a servo means writing the
         chip's timer registers, and that is no longer this core's vocabulary. */
    CPP

    PERIPHERAL = <<~CPP
      #include "bareruby_binding.h"

      #include <Arduino.h>

      #include <stdarg.h>
      #include <stdio.h>
      #include <string.h>

      /* printf writes to a stream, and on this libc there is no stream until one is made.
         The console is the board's USB-serial bridge, and both of the runtime's channels
         are pointed at it: fd1 is what puts reaches and fd2 is where a panic says so. */
      static int bareruby_console_put(char byte, FILE *stream) {
          (void)stream;
          Serial.write((uint8_t)byte);
          return 0;
      }

      static FILE bareruby_console;

      void bareruby_startup(void) {
          Serial.begin(#{CONSOLE_BAUD});
          fdev_setup_stream(&bareruby_console, bareruby_console_put, NULL, _FDEV_SETUP_WRITE);
          stdout = &bareruby_console;
          stderr = &bareruby_console;
      }




      /* The uart_interrupt unit overrides this when a program says on_line; otherwise
         sleep drains nothing and pays one empty call per millisecond. */
      extern "C" __attribute__((weak)) void bareruby_uart_interrupt_drain(void) {}

      /* delayMicroseconds takes an unsigned int, which is 16 bits here, and is accurate
         only well below its top. So a long wait is spent in whole milliseconds and the
         remainder is what the core is asked for. */
      void bareruby_machine_delay_us(int32_t microseconds) {
          while (microseconds >= 1000) {
              delay(1);
              microseconds -= 1000;
          }
          if (microseconds > 0) {
              delayMicroseconds((unsigned int)microseconds);
          }
      }

      /* The signed-difference comparison carries a millis() wrap, as the asleep mark
         below does with micros(). */
      void bareruby_sleep_ms(int32_t milliseconds) {
          uint32_t deadline = millis() + (uint32_t)(milliseconds > 0 ? milliseconds : 0);
          for (;;) {
              bareruby_uart_interrupt_drain();
              if ((int32_t)(deadline - millis()) <= 0) {
                  break;
              }
              delay(1);
          }
      }

      void bareruby_sleep(int32_t seconds) {
          bareruby_sleep_ms(seconds > 0 ? seconds * 1000 : 0);
      }

      /* One mark serves all three units, counted in microseconds since the core started
         its clock. It is 32 bits, which is what micros() answers, so it wraps after some
         71 minutes; the comparison is written as a signed difference, which carries the
         wrap correctly as long as no single wait is longer than half of that. */
      static uint32_t bareruby_asleep_mark;

      static void bareruby_asleep_until(uint32_t interval) {
          uint32_t deadline = bareruby_asleep_mark + interval;
          while ((int32_t)(deadline - micros()) > 0) {
          }
          bareruby_asleep_mark = micros();
      }

      void bareruby_asleep(int32_t seconds) {
          bareruby_asleep_until((uint32_t)seconds * 1000000ul);
      }

      void bareruby_asleep_ms(int32_t milliseconds) {
          bareruby_asleep_until((uint32_t)milliseconds * 1000ul);
      }

      void bareruby_asleep_us(int32_t microseconds) {
          bareruby_asleep_until((uint32_t)microseconds);
      }

      int32_t bareruby_ticks_ms(void) {
          return (int32_t)millis();
      }
    CPP

    UART_RECEIVE = <<~CPP
      #include "bareruby_binding.h"

      #include <Arduino.h>

      static HardwareSerial *bareruby_uart_receive_port(const bareruby_uart_t *self) {
          switch (self->id) {
          case 1: return &Serial1;
          case 2: return &Serial2;
          case 3: return &Serial3;
          default: return &Serial;
          }
      }

      static int bareruby_uart_receive_byte(HardwareSerial *port) {
          while (port->available() <= 0) {
          }
          return port->read();
      }

      bareruby_string_t *bareruby_uart_read(
          bareruby_uart_t *self, bareruby_arena_t *arena, int32_t length) {
          HardwareSerial *port = bareruby_uart_receive_port(self);
          bareruby_string_t *result = bareruby_string_new(arena, "");
          for (int32_t index = 0; index < length; ++index) {
              bareruby_string_append_byte(result, bareruby_uart_receive_byte(port));
          }
          return result;
      }

      bareruby_string_t *bareruby_uart_gets(bareruby_uart_t *self, bareruby_arena_t *arena) {
          HardwareSerial *port = bareruby_uart_receive_port(self);
          bareruby_string_t *result = bareruby_string_new(arena, "");
          int byte;
          do {
              byte = bareruby_uart_receive_byte(port);
              bareruby_string_append_byte(result, byte);
          } while (byte != '\\n');
          return result;
      }
    CPP

    # The receive interrupt. **The ISR here is HardwareSerial's own** — the core defines
    # ISR(USARTn_RX_vect) for every port and Serial is always linked as the console, so a
    # vector of this unit's own would be a duplicate-vector link error. The core's
    # interrupt-filled rx buffer stands in for the ring the other bindings keep, and the
    # drain empties it in thread mode into the same line assembly, so LF/CRLF, the
    # 255-byte cap and the overlong discard behave byte for byte the same.
    UART_INTERRUPT = <<~CPP
      #include "bareruby_binding.h"

      #include <Arduino.h>

      typedef struct {
          char line[256];               /* the 256 bytes on_line costs; the view points here */
          int32_t line_length;
          bool discarding;              /* an overlong line, thrown away to the next LF */
          bareruby_uart_line_handler_t handler;
          HardwareSerial *port;
      } bareruby_uart_interrupt_t;

      static bareruby_uart_interrupt_t bareruby_uart_interrupt;

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

      /* The core's buffer has one consumer. A registered handler is it, and the drain
         assembles lines; without one the bytes wait for the read family below. */
      extern "C" void bareruby_uart_interrupt_drain(void) {
          HardwareSerial *port = bareruby_uart_interrupt.port;
          if (port == NULL || bareruby_uart_interrupt.handler == NULL) {
              return;
          }
          while (port->available() > 0) {
              bareruby_uart_interrupt_line_byte((uint8_t)port->read());
          }
      }

      static HardwareSerial *bareruby_uart_interrupt_attach(bareruby_uart_t *self) {
          if (bareruby_uart_interrupt.port == NULL) {
              switch (self->id) {
              case 1: bareruby_uart_interrupt.port = &Serial1; break;
              case 2: bareruby_uart_interrupt.port = &Serial2; break;
              case 3: bareruby_uart_interrupt.port = &Serial3; break;
              default: bareruby_uart_interrupt.port = &Serial; break;
              }
          }
          return bareruby_uart_interrupt.port;
      }

      void bareruby_uart_on_line(bareruby_uart_t *self, bareruby_uart_line_handler_t handler) {
          bareruby_uart_interrupt.handler = handler;
          bareruby_uart_interrupt_attach(self);
      }

      int32_t bareruby_uart_read_byte(bareruby_uart_t *self) {
          return (int32_t)bareruby_uart_interrupt_attach(self)->read();
      }

      int32_t bareruby_uart_peek(bareruby_uart_t *self) {
          return (int32_t)bareruby_uart_interrupt_attach(self)->peek();
      }

      /* The strong definition; the polling one in the uart unit is weak. */
      int32_t bareruby_uart_bytes_available(bareruby_uart_t *self) {
          return (int32_t)bareruby_uart_interrupt_attach(self)->available();
      }
    CPP

    # This board has one bus, so the id names nothing to choose between and Wire is it.
    # SDA is pin 20 and SCL pin 21, which the core knows and this side does not say.
    I2C = <<~CPP
      #include "bareruby_binding.h"

      #include <Arduino.h>
      #include <Wire.h>

      void bareruby_i2c_init(bareruby_i2c_t *self, int32_t id, int32_t frequency) {
          self->id = id;
          self->frequency = frequency;
          Wire.begin();
          Wire.setClock((uint32_t)frequency);
      }

      int32_t bareruby_i2c_write(
          bareruby_i2c_t *self, int32_t address, const char *bytes, int32_t length) {
          (void)self;
          Wire.beginTransmission((uint8_t)address);
          Wire.write((const uint8_t *)bytes, (size_t)length);
          return Wire.endTransmission(true) == 0 ? length : -1;
      }
    CPP

    I2C_READ = <<~CPP
      #include "bareruby_binding.h"

      #include <Arduino.h>
      #include <Wire.h>

      bareruby_string_t *bareruby_i2c_read(
          bareruby_i2c_t *self, bareruby_arena_t *arena, int32_t address, int32_t length,
          const char *outputs, int32_t output_length) {
          (void)self;
          if (0 < output_length) {
              Wire.beginTransmission((uint8_t)address);
              Wire.write((const uint8_t *)outputs, (size_t)output_length);
              Wire.endTransmission(false);
          }

          Wire.requestFrom((uint8_t)address, (uint8_t)length);
          bareruby_string_t *result = bareruby_string_new(arena, "");
          while (Wire.available() > 0) {
              bareruby_string_append_byte(result, Wire.read());
          }
          return result;
      }
    CPP

    # The core spells the peripherals the same way on every board it reaches, so one
    # implementation serves all of them and only the board name handed to the build tells
    # them apart. That is the same shape the Pico boards have, one step wider: these
    # boards do not even share an instruction set.
    PWM_FILE = "bareruby_binding_pwm_arduino.cpp"
    ADC_FILE = "bareruby_binding_adc_arduino.cpp"
    UART_FILE = "bareruby_binding_uart_arduino.cpp"
    GPIO_FILE = "bareruby_binding_gpio_arduino.cpp"
    PERIPHERAL_FILE = "bareruby_binding_arduino.cpp"
    UART_RECEIVE_FILE = "bareruby_binding_uart_receive_arduino.cpp"
    UART_INTERRUPT_FILE = "bareruby_binding_uart_interrupt_arduino.cpp"
    I2C_FILE = "bareruby_binding_i2c_arduino.cpp"
    I2C_READ_FILE = "bareruby_binding_i2c_read_arduino.cpp"

    # A board whose indicator is on a pin, and which pin is the core's answer: every board
    # it reaches defines LED_BUILTIN, so a board that puts its LED elsewhere needs no
    # change here.
    ONBOARD_LED_PIN = <<~CPP
      #include "bareruby_binding.h"

      #include <Arduino.h>

      void bareruby_onboard_led_init(bareruby_onboard_led_t *self) {
          self->state = 0;
          pinMode(LED_BUILTIN, OUTPUT);
      }

      void bareruby_onboard_led_write(bareruby_onboard_led_t *self, int32_t value) {
          self->state = (value != 0) ? 1 : 0;
          digitalWrite(LED_BUILTIN, self->state != 0 ? HIGH : LOW);
      }

      void bareruby_onboard_led_on(bareruby_onboard_led_t *self) {
          bareruby_onboard_led_write(self, 1);
      }

      void bareruby_onboard_led_off(bareruby_onboard_led_t *self) {
          bareruby_onboard_led_write(self, 0);
      }
    CPP

    ONBOARD_LED_PIN_FILE = "bareruby_binding_onboard_led_arduino_pin.cpp"

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
      ONBOARD_LED_PIN_FILE => ONBOARD_LED_PIN
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

    # The core owns main and calls into the program, so this side names its translation
    # unit after the program rather than after an entry point it does not own.
    PROGRAM_FILE = "bareruby_program.cpp"

    def self.key = :arduino

    def self.tools = ArduinoTools

    def self.toolchain = ArduinoToolchain

    def self.flash = ArduinoFlash

    def self.build = ArduinoBuild
  end
end

# One machine to a file, so that teaching this binding a new machine is adding a file.
Dir.children(File.expand_path("machine", __dir__)).sort.grep(/\.rb\z/).each do |entry|
  require_relative "machine/#{entry}"
end
