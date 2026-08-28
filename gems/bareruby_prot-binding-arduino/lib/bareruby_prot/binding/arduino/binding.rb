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

      /* **Whether a frequency can be obeyed is the core's answer, and it is not the same
         answer on both architectures this binding reaches.** An AVR's analogWrite takes
         its frequency from whichever timer the pin sits on and offers no way to name
         another, so the number is remembered and nothing else; an ESP32 puts each line on
         a channel whose frequency is settable, so it is obeyed. Remembering it is what
         both need, because a pulse width is turned into a duty against it. */
      static void bareruby_pwm_settle_frequency(bareruby_pwm_t *self, int32_t frequency) {
          self->frequency = frequency;
      #ifdef ARDUINO_ARCH_ESP32
          if (frequency > 0) {
              analogWriteFrequency((uint8_t)self->pin, (uint32_t)frequency);
          }
      #endif
      }

      void bareruby_pwm_init(bareruby_pwm_t *self, int32_t pin, int32_t frequency, int32_t duty) {
          self->pin = pin;
          self->slice = 0;
          pinMode((uint8_t)pin, OUTPUT);
          bareruby_pwm_settle_frequency(self, frequency);
          bareruby_pwm_apply_duty(self, duty);
      }

      void bareruby_pwm_apply_frequency(bareruby_pwm_t *self, int32_t frequency) {
          bareruby_pwm_settle_frequency(self, frequency);
      }

      void bareruby_pwm_apply_period_us(bareruby_pwm_t *self, int32_t period_us) {
          bareruby_pwm_settle_frequency(self, period_us > 0 ? (int32_t)(1000000 / period_us) : 0);
      }

      void bareruby_pwm_apply_duty(bareruby_pwm_t *self, int32_t duty) {
          analogWrite((uint8_t)self->pin, (int)(255 * duty / 100));
      }

      void bareruby_pwm_apply_pulse_width_us(bareruby_pwm_t *self, int32_t pulse_width_us) {
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

      /* **How wide the converter is and what it reads full scale are the board's**, and
         they arrive as definitions: ten bits against a 5 V reference on one of these
         boards, twelve against the 3.1 V the widest attenuation reaches on the other.
         read answers volts either way, which is what keeps a program that reads a voltage
         from carrying the board's numbers.

         What a channel is, is the board's too — the analog input's own number on an AVR
         and the pin's GPIO number on an ESP32 — and analogRead takes whichever of the two
         that core speaks, so it is passed through as written.

         The divisor is widened before it is multiplied out. An int is 16 bits on one of
         these machines, and 1023 * 1000 written as two ints does not fit in one. */
      void bareruby_adc_init(bareruby_adc_t *self, int32_t pin) {
          self->pin = pin;
          self->channel = pin;
      }

      int32_t bareruby_adc_read_raw(bareruby_adc_t *self) {
          return (int32_t)analogRead((uint8_t)self->channel);
      }

      int32_t bareruby_adc_read(bareruby_adc_t *self) {
          int64_t raw = (int64_t)bareruby_adc_read_raw(self);
          return (int32_t)((raw * BARERUBY_ADC_MILLIVOLTS * 65536) /
                           ((int64_t)BARERUBY_ADC_RESOLUTION * 1000));
      }
    CPP

    UART = <<~CPP
      #include "bareruby_binding.h"
      #include <Arduino.h>
      #include <stdarg.h>
      #include <stdio.h>
      #include <string.h>

      /* **How many lines a board brings out is not the same through this core on both
         architectures.** A Mega has four USARTs and an ESP32-S3 has three, of which this
         binding reaches the two the board wires up. Unit 0 is the console either way: on
         one board that is the USB bridge, on the other the pins the bridge chip is on. */
      static HardwareSerial *bareruby_uart_port(const bareruby_uart_t *self) {
          switch (self->unit) {
      #ifdef BARERUBY_UART3_TXD_PIN
          case 3: return &Serial3;
      #endif
      #ifdef BARERUBY_UART2_TXD_PIN
          case 2: return &Serial2;
      #endif
          case 1: return &Serial1;
          default: return &Serial;
          }
      }

      /* **Which pin a line comes out on is the board's**, and it arrives as a definition
         rather than as a number written into this unit — so the next board through this
         binding is a file in machine/ and nothing else. Two things need it: a break, which
         no core here offers a call for, and opening a line on an ESP32, where the pins can
         be moved and therefore have to be said. */
      static int32_t bareruby_uart_transmit_pin(const bareruby_uart_t *self) {
          switch (self->unit) {
      #ifdef BARERUBY_UART3_TXD_PIN
          case 3: return BARERUBY_UART3_TXD_PIN;
      #endif
      #ifdef BARERUBY_UART2_TXD_PIN
          case 2: return BARERUBY_UART2_TXD_PIN;
      #endif
          case 1: return BARERUBY_UART1_TXD_PIN;
          default: return BARERUBY_UART0_TXD_PIN;
          }
      }

      #ifdef ARDUINO_ARCH_ESP32
      static int32_t bareruby_uart_receive_pin(const bareruby_uart_t *self) {
          switch (self->unit) {
          case 1: return BARERUBY_UART1_RXD_PIN;
          default: return BARERUBY_UART0_RXD_PIN;
          }
      }
      #endif

      /* **The frame is one number, and how it is spelled is the core's.** An AVR lays the
         three fields out as separate bits of one byte — data bits in 2..1, stop bits in 3,
         parity in 5..4 — and an ESP32 lays them out differently in a word carrying a
         marker above them. Building the number beats a table of thirty-six names either
         way, and that a table would have had to be written twice is the point. */
      #ifdef ARDUINO_ARCH_ESP32
      static uint32_t bareruby_uart_configuration(
          int32_t data_bits, int32_t stop_bits, int32_t parity) {
          uint32_t configuration = 0x8000000u | (uint32_t)((data_bits - 1) << 2);
          if (stop_bits == 2) {
              configuration |= 0x20u;
          }
          if (parity == 1) {
              configuration |= 0x02u;
          } else if (parity == 2) {
              configuration |= 0x03u;
          }
          return configuration;
      }
      #else
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
      #endif

      /* What the line is opened with, applied. The constructor and setmode differ only in
         where the values came from, so both end here.

         **Which pins a port is on is the board's, not the program's.** One core reaches a
         USART's own pins and offers no way to move them; the other reaches pins that can
         be moved, and is told the board's. Neither has hardware flow control here — so a
         line asked for on other pins, or with RTS/CTS, is a line this binding does not
         open. It is refused rather than opened somewhere else.

         **How deep the receive queue is, is the core's on one board and the program's on
         the other.** An ESP32's driver takes a size before the line is opened, so a size
         the program asked for is given to it here. */
      static void bareruby_uart_apply(bareruby_uart_t *self) {
          if (self->txd_pin >= 0 || self->rxd_pin >= 0 || self->flow_control != 0 ||
              self->rts_pin >= 0 || self->cts_pin >= 0) {
              bareruby_panic("UART: the pins and flow control here are the board's");
          }
      #ifdef ARDUINO_ARCH_ESP32
      #ifdef BARERUBY_UART_RX_BUFFER_SIZE
          bareruby_uart_port(self)->setRxBufferSize(BARERUBY_UART_RX_BUFFER_SIZE);
      #endif
          bareruby_uart_port(self)->begin(
              (unsigned long)self->baudrate,
              bareruby_uart_configuration(self->data_bits, self->stop_bits, self->parity),
              (int8_t)bareruby_uart_receive_pin(self),
              (int8_t)bareruby_uart_transmit_pin(self));
      #else
          bareruby_uart_port(self)->begin(
              (unsigned long)self->baudrate,
              bareruby_uart_configuration(self->data_bits, self->stop_bits, self->parity));
      #endif
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
          bareruby_uart_apply(self);
      }

      void bareruby_uart_setmode(
          bareruby_uart_t *self, int32_t baudrate, int32_t data_bits, int32_t stop_bits,
          int32_t parity, int32_t flow_control, int32_t rts_pin, int32_t cts_pin) {
          bareruby_uart_settle(self, baudrate, data_bits, stop_bits, parity, flow_control,
                               rts_pin, cts_pin);
          bareruby_uart_apply(self);
      }

      int32_t bareruby_uart_write(bareruby_uart_t *self, const char *value) {
          size_t length = strlen(value);
          bareruby_uart_port(self)->write((const uint8_t *)value, length);
          return (int32_t)length;
      }

      /* **What ends a line is the line's, not the compiler's.** puts puts the ending the
         class was given; write puts nothing after what it was handed, whether or not the
         program wrote an interpolation. */
      void bareruby_uart_puts(bareruby_uart_t *self, const char *value) {
          (void)bareruby_uart_write(self, value);
          (void)bareruby_uart_write(self, self->line_ending);
      }

      void bareruby_uart_printf(bareruby_uart_t *self, const char *format, ...) {
          char payload[128];
          va_list arguments;
          va_start(arguments, format);
          vsnprintf(payload, sizeof(payload), format, arguments);
          va_end(arguments);
          (void)bareruby_uart_write(self, payload);
      }

      void bareruby_uart_printf_line(bareruby_uart_t *self, const char *format, ...) {
          char payload[128];
          va_list arguments;
          va_start(arguments, format);
          vsnprintf(payload, sizeof(payload), format, arguments);
          va_end(arguments);
          bareruby_uart_puts(self, payload);
      }

      /* Weak for the same shape the other bindings have, though HardwareSerial's own
         count is already the buffered answer; the uart_interrupt unit's override only
         adds the arming touch. */
      __attribute__((weak)) int32_t bareruby_uart_bytes_available(bareruby_uart_t *self) {
          return (int32_t)bareruby_uart_port(self)->available();
      }

      /* availableForWrite reports the room left before a write would wait, so what is
         still owed is the whole of that room less what is free, plus the frame in the
         shift register -- which no core here exposes, so it is not counted. **How much
         room there is, is the core's**: a ring of a size the AVR core names, and on an
         ESP32 the hardware FIFO the line drains from. */
      int32_t bareruby_uart_bytes_to_write(bareruby_uart_t *self) {
      #ifdef ARDUINO_ARCH_ESP32
          return (int32_t)(SOC_UART_FIFO_LEN - bareruby_uart_port(self)->availableForWrite());
      #else
          return (int32_t)(SERIAL_TX_BUFFER_SIZE - 1 - bareruby_uart_port(self)->availableForWrite());
      #endif
      }

      /* **Neither core offers a break at all.** One is sent by taking the pin back from
         the transmitter and holding it low, so that is what this does: drain, release the
         port, drive the pin, and open the line again from what the program asked for --
         which is the one place the frame kept in the struct is read back. */
      void bareruby_uart_break(bareruby_uart_t *self, int32_t milliseconds) {
          HardwareSerial *port = bareruby_uart_port(self);
          uint8_t pin = (uint8_t)bareruby_uart_transmit_pin(self);
          port->flush();
          port->end();
          pinMode(pin, OUTPUT);
          digitalWrite(pin, LOW);
          delay((unsigned long)(milliseconds > 0 ? milliseconds : 0));
          digitalWrite(pin, HIGH);
          bareruby_uart_apply(self);
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

      /* **Whether a pin can be pulled down is the chip's answer and not the program's**,
         and the two chips this core reaches here do not agree: an AVR has pull-ups only,
         so a pin asked for the other is left plain rather than given the wrong one, and an
         ESP32 has both. The core says which by whether it defines the mode at all, which
         is a more honest question to ask than the architecture. It is the same reason a
         pin with no converter channel is passed through as written. */
      void bareruby_gpio_init(bareruby_gpio_t *self, int32_t pin, int32_t params) {
          self->pin = pin;
          self->params = params;
          if (params & 2) {
              pinMode((uint8_t)pin, OUTPUT);
          } else if (params & 8) {
              pinMode((uint8_t)pin, INPUT_PULLUP);
      #ifdef INPUT_PULLDOWN
          } else if (params & 16) {
              pinMode((uint8_t)pin, INPUT_PULLDOWN);
      #endif
          } else {
              pinMode((uint8_t)pin, INPUT);
          }
      }

      int32_t bareruby_gpio_write(bareruby_gpio_t *self, int32_t value) {
          digitalWrite((uint8_t)self->pin, value != 0 ? HIGH : LOW);
          return 0;
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

      void bareruby_gpio_irq(
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

      /* **Where printf already goes is the libc's answer, and the two libcs here differ.**
         On an AVR there is no stream until one is made, so one is made over the port the
         board's USB-serial bridge is on and both of the runtime's channels are pointed at
         it — fd1 is what puts reaches and fd2 is where a panic says so. On an ESP32 the
         console is already a UART the system opened before this ran, and it is the one
         this board brings out through its bridge chip; opening the line here is what makes
         it the port the program can also write to as unit 0. */
      #ifdef ARDUINO_ARCH_ESP32
      void bareruby_startup(void) {
          Serial.begin(#{CONSOLE_BAUD});
      }
      #else
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
      #endif




      /* The uart_interrupt unit overrides this when a program registers an irq;
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
         below does with micros(). The wait is counted unsigned for the same reason the
         mark is, so that the seconds form can turn its argument into milliseconds
         without overflowing a signed multiplication. */
      static void bareruby_sleep_for(uint32_t milliseconds, bool interrupt) {
          uint32_t deadline = millis() + milliseconds;
          for (;;) {
              if (interrupt) {
                  bareruby_uart_interrupt_drain();
              }
              if ((int32_t)(deadline - millis()) <= 0) {
                  break;
              }
              delay(1);
          }
      }

      int32_t bareruby_sleep_ms(int32_t milliseconds, bool interrupt) {
          bareruby_sleep_for(milliseconds > 0 ? (uint32_t)milliseconds : 0u, interrupt);
          return milliseconds;
      }

      int32_t bareruby_sleep(int32_t seconds, bool interrupt) {
          bareruby_sleep_for(seconds > 0 ? (uint32_t)seconds * 1000u : 0u, interrupt);
          return seconds;
      }

      /* One mark serves all three units, counted in microseconds since the core started
         its clock. It is 32 bits, which is what micros() answers, so it wraps after some
         71 minutes; the comparison is written as a signed difference, which carries the
         wrap correctly as long as no single wait is longer than half of that. */
      static uint32_t bareruby_asleep_mark;

      /* **A period is only long enough to deliver in if it is longer than delivering
         takes.** So the wait is spent in whole milliseconds while more than one of them
         remains, and what is left is the spin below: a 25 us period keeps its exactness
         and delivers nothing, which is the honest answer for a period that has no room
         for a handler. Notifications are not lost by it — the core's own interrupt keeps
         filling its buffer, and the next wait long enough will hand them over. */
      static void bareruby_asleep_until(uint32_t interval, bool interrupt) {
          uint32_t deadline = bareruby_asleep_mark + interval;
          while (interrupt && (int32_t)(deadline - micros()) > 1000) {
              bareruby_uart_interrupt_drain();
              delay(1);
          }
          while ((int32_t)(deadline - micros()) > 0) {
          }
          bareruby_asleep_mark = micros();
      }

      void bareruby_asleep(int32_t seconds, bool interrupt) {
          bareruby_asleep_until((uint32_t)seconds * 1000000ul, interrupt);
      }

      void bareruby_asleep_ms(int32_t milliseconds, bool interrupt) {
          bareruby_asleep_until((uint32_t)milliseconds * 1000ul, interrupt);
      }

      void bareruby_asleep_us(int32_t microseconds, bool interrupt) {
          bareruby_asleep_until((uint32_t)microseconds, interrupt);
      }

      int32_t bareruby_ticks_ms(void) {
          return (int32_t)millis();
      }
    CPP

    UART_RECEIVE = <<~CPP
      #include "bareruby_binding.h"

      #include <Arduino.h>

      /* **The one queue the receive side has, and here it is the core's own.**
         HardwareSerial already fills a ring from its interrupt, so this binding buys no
         second one: whoever asks first takes what is in that. A handler and a program
         calling getbyte are the same kind of consumer, reaching it through the same
         call. Emptying it is the uart unit's clear_rx_buffer, which is already the same
         buffer — so there is nothing to override here. */
      /* **Whether the size of this queue is this binding's to choose is the core's
         answer.** The AVR core declares the buffer at compile time and fills it from its
         own interrupt, so a program asking for another size is asking that board for
         something it cannot give — and the build stops where the number is rather than
         running quietly with a different one. An ESP32's driver is told a size before the
         line is opened, so the number is given to it there, in the unit that opens lines.
         Saying nothing gets the core's own size on either. */
      #if defined(BARERUBY_UART_RX_BUFFER_SIZE) && !defined(ARDUINO_ARCH_ESP32)
      #if BARERUBY_UART_RX_BUFFER_SIZE != SERIAL_RX_BUFFER_SIZE
      #error "rx_buffer_size: the core owns the receive queue here, and its size is SERIAL_RX_BUFFER_SIZE"
      #endif
      #endif

      static HardwareSerial *bareruby_uart_receive_port(bareruby_uart_t *self) {
          switch (self->unit) {
      #ifdef BARERUBY_UART3_TXD_PIN
          case 3: return &Serial3;
      #endif
      #ifdef BARERUBY_UART2_TXD_PIN
          case 2: return &Serial2;
      #endif
          case 1: return &Serial1;
          default: return &Serial;
          }
      }

      int32_t bareruby_uart_getbyte(bareruby_uart_t *self) {
          return (int32_t)bareruby_uart_receive_port(self)->read();
      }

      int32_t bareruby_uart_peek(bareruby_uart_t *self) {
          return (int32_t)bareruby_uart_receive_port(self)->peek();
      }

      /* The strong definition; the polling one in the uart unit is weak. */
      int32_t bareruby_uart_bytes_available(bareruby_uart_t *self) {
          return (int32_t)bareruby_uart_receive_port(self)->available();
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

    # **How many buses a board has, and where they come out, is the board's answer.** One
    # of these has a single bus on pins the chip fixes, which the core knows and this side
    # does not say; the other has two, on pins that can be moved and therefore arrive from
    # machine/ as definitions. A unit nothing is wired for falls to the first.
    I2C_BUS = <<~CPP
      #ifdef BARERUBY_I2C1_SDA_PIN
      static TwoWire *bareruby_i2c_bus(const bareruby_i2c_t *self) {
          return self->unit == 1 ? &Wire1 : &Wire;
      }
      #else
      static TwoWire *bareruby_i2c_bus(const bareruby_i2c_t *self) {
          (void)self;
          return &Wire;
      }
      #endif
    CPP

    I2C = <<~CPP
      #include "bareruby_binding.h"

      #include <Arduino.h>
      #include <Wire.h>

      #{I2C_BUS}
      void bareruby_i2c_init(bareruby_i2c_t *self, int32_t unit, int32_t frequency) {
          self->unit = unit;
          self->frequency = frequency;
      #ifdef BARERUBY_I2C1_SDA_PIN
          if (unit == 1) {
              Wire1.begin(BARERUBY_I2C1_SDA_PIN, BARERUBY_I2C1_SCL_PIN, (uint32_t)frequency);
          } else {
              Wire.begin(BARERUBY_I2C0_SDA_PIN, BARERUBY_I2C0_SCL_PIN, (uint32_t)frequency);
          }
      #else
          Wire.begin();
          Wire.setClock((uint32_t)frequency);
      #endif
      }

      int32_t bareruby_i2c_write(
          bareruby_i2c_t *self, int32_t address, const char *bytes, int32_t length) {
          TwoWire *bus = bareruby_i2c_bus(self);
          bus->beginTransmission((uint8_t)address);
          bus->write((const uint8_t *)bytes, (size_t)length);
          return bus->endTransmission(true) == 0 ? length : -1;
      }
    CPP

    I2C_READ = <<~CPP
      #include "bareruby_binding.h"

      #include <Arduino.h>
      #include <Wire.h>

      #{I2C_BUS}
      bareruby_string_t *bareruby_i2c_read(
          bareruby_i2c_t *self, bareruby_arena_t *arena, int32_t address, int32_t length,
          const char *outputs, int32_t output_length) {
          TwoWire *bus = bareruby_i2c_bus(self);
          if (0 < output_length) {
              bus->beginTransmission((uint8_t)address);
              bus->write((const uint8_t *)outputs, (size_t)output_length);
              bus->endTransmission(false);
          }

          bus->requestFrom((uint8_t)address, (uint8_t)length);
          bareruby_string_t *result = bareruby_string_new(arena, "");
          while (bus->available() > 0) {
              bareruby_string_append_byte(result, bus->read());
          }
          return result;
      }
    CPP

    # One implementation of each peripheral serves every board this core reaches, which is
    # the same shape the Pico boards have, one step wider: these boards do not even share
    # an instruction set. **The core does not quite spell every peripheral the same way on
    # both of them**, and where it does not, the unit asks — the board's own numbers by the
    # names they arrive under, and the core's own by what it defines.
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

    # A board whose indicator is not on a pin at all, but is one addressable device on a
    # wire: twenty-four bits of colour at a bit period no loop of stores can keep. The core
    # carries the transmitter that exists for exactly that, so the whole of driving it is
    # one call. **Which pin it is on is the board's**, and arrives as a definition.
    ONBOARD_LED_RGB = <<~CPP
      #include "bareruby_binding.h"

      #include <Arduino.h>

      /* **An indicator answers on or off, and this one takes a colour** — so "on" is a
         level of white low enough to be looked at rather than the full scale that makes
         one of these painful. */
      #define BARERUBY_LED_ON 32

      void bareruby_onboard_led_write(bareruby_onboard_led_t *self, int32_t value) {
          self->state = (value != 0) ? 1 : 0;
          uint8_t level = self->state ? BARERUBY_LED_ON : 0;
          rgbLedWrite(BARERUBY_ONBOARD_LED_PIN, level, level, level);
      }

      void bareruby_onboard_led_init(bareruby_onboard_led_t *self) {
          bareruby_onboard_led_write(self, 0);
      }

      void bareruby_onboard_led_on(bareruby_onboard_led_t *self) {
          bareruby_onboard_led_write(self, 1);
      }

      void bareruby_onboard_led_off(bareruby_onboard_led_t *self) {
          bareruby_onboard_led_write(self, 0);
      }
    CPP

    ONBOARD_LED_RGB_FILE = "bareruby_binding_onboard_led_arduino_rgb.cpp"

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
      ONBOARD_LED_PIN_FILE => ONBOARD_LED_PIN,
      ONBOARD_LED_RGB_FILE => ONBOARD_LED_RGB
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
