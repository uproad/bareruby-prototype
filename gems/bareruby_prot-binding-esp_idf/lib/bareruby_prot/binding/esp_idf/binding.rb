# frozen_string_literal: true

module BareRubyProt
  module EspIdfBinding
    # Everything a program is given whatever it reaches for: the clock, the waits, and the
    # one call every build makes before the program starts.
    #
    # **A wait is where a notification is delivered**, and on this chip a wait is also
    # where every other task gets to run — so it is spent in FreeRTOS ticks rather than
    # spun through. The tick is a millisecond here, which the build says in its own
    # configuration; at the ten milliseconds FreeRTOS ships with, `sleep 0.001` would be a
    # ten-millisecond wait and every short one would be wrong by an order of magnitude.
    PERIPHERAL = <<~CPP
      #include "bareruby_binding.h"

      #include "esp_rom_sys.h"
      #include "esp_timer.h"
      #include "freertos/FreeRTOS.h"
      #include "freertos/task.h"

      /* The uart_interrupt unit overrides this when a program registers an irq; sleep
         drains nothing and pays one empty call per millisecond. */
      extern "C" __attribute__((weak)) void bareruby_uart_interrupt_drain(void) {}

      /* Nothing has to be started here. The console is up before app_main is called, and
         every peripheral this binding reaches brings itself up when it is first named. */
      void bareruby_startup(void) {
      }

      /* Microseconds are shorter than the scheduler's smallest step, so this is the one
         wait that is spun rather than slept. */
      void bareruby_machine_delay_us(int32_t microseconds) {
          esp_rom_delay_us((uint32_t)(microseconds > 0 ? microseconds : 0));
      }

      static int64_t bareruby_now_us(void) {
          return esp_timer_get_time();
      }

      static void bareruby_sleep_for(int64_t milliseconds, bool interrupt) {
          int64_t deadline = bareruby_now_us() + milliseconds * 1000;
          for (;;) {
              if (interrupt) {
                  bareruby_uart_interrupt_drain();
              }
              if (bareruby_now_us() >= deadline) {
                  break;
              }
              vTaskDelay(1);
          }
      }

      int32_t bareruby_sleep_ms(int32_t milliseconds, bool interrupt) {
          bareruby_sleep_for(milliseconds > 0 ? milliseconds : 0, interrupt);
          return milliseconds;
      }

      int32_t bareruby_sleep(int32_t seconds, bool interrupt) {
          bareruby_sleep_for(seconds > 0 ? (int64_t)seconds * 1000 : 0, interrupt);
          return seconds;
      }

      /* One mark serves all three units, and it counts microseconds since boot in 64
         bits. Zero is boot time, so the first call needs no flag of its own. A late turn
         does not try to catch up — the mark moves to the actual return and the missed time
         is gone, which keeps one slow turn from firing the next ones back to back. */
      static int64_t bareruby_asleep_mark = 0;

      /* **A period is only long enough to deliver in if it is longer than delivering
         takes.** So the wait is spent in whole ticks while more than one of them remains,
         and what is left is spun out to the deadline: a 25 us period keeps its exactness
         and delivers nothing, which is the honest answer for a period that has no room for
         a handler. Notifications are not lost by it — the driver keeps filling its queue,
         and the next wait long enough will hand them over. */
      static void bareruby_asleep_until(int64_t interval, bool interrupt) {
          int64_t deadline = bareruby_asleep_mark + interval;
          while (interrupt && bareruby_now_us() + 1000 < deadline) {
              bareruby_uart_interrupt_drain();
              vTaskDelay(1);
          }
          while (bareruby_now_us() + 1000 < deadline) {
              vTaskDelay(1);
          }
          int64_t remaining = deadline - bareruby_now_us();
          if (remaining > 0) {
              esp_rom_delay_us((uint32_t)remaining);
          }
          bareruby_asleep_mark = bareruby_now_us();
      }

      void bareruby_asleep(int32_t seconds, bool interrupt) {
          bareruby_asleep_until((int64_t)seconds * 1000000, interrupt);
      }

      void bareruby_asleep_ms(int32_t milliseconds, bool interrupt) {
          bareruby_asleep_until((int64_t)milliseconds * 1000, interrupt);
      }

      void bareruby_asleep_us(int32_t microseconds, bool interrupt) {
          bareruby_asleep_until((int64_t)microseconds, interrupt);
      }

      int32_t bareruby_ticks_ms(void) {
          return (int32_t)(bareruby_now_us() / 1000);
      }
    CPP

    # A pin. **A peripheral that can be uninstalled cannot share a file with one that
    # cannot** — the declarations go with the gem, and an implementation left behind would
    # have nothing to implement against.
    GPIO = <<~CPP
      #include "bareruby_binding.h"

      #include "driver/gpio.h"

      static bareruby_interrupt_handler_t bareruby_gpio_interrupt_handler;

      static void bareruby_gpio_interrupt_callback(void *argument) {
          (void)argument;
          bareruby_gpio_interrupt_handler();
      }

      /* The mode is one answer here rather than a direction and a drive: this driver
         spells open drain as a mode of its own, and a pin asked for nothing at all is
         disconnected rather than merely unread. */
      static gpio_mode_t bareruby_gpio_mode(int32_t params) {
          if (params & 4) {
              return GPIO_MODE_DISABLE;
          }
          if (params & 2) {
              return (params & 32) ? GPIO_MODE_OUTPUT_OD : GPIO_MODE_OUTPUT;
          }
          return GPIO_MODE_INPUT;
      }

      void bareruby_gpio_init(bareruby_gpio_t *self, int32_t pin, int32_t params) {
          self->pin = pin;
          self->params = params;
          gpio_config_t settings = {};
          settings.pin_bit_mask = 1ULL << pin;
          settings.mode = bareruby_gpio_mode(params);
          settings.pull_up_en = (params & 8) ? GPIO_PULLUP_ENABLE : GPIO_PULLUP_DISABLE;
          settings.pull_down_en = (params & 16) ? GPIO_PULLDOWN_ENABLE : GPIO_PULLDOWN_DISABLE;
          settings.intr_type = GPIO_INTR_DISABLE;
          gpio_config(&settings);
      }

      int32_t bareruby_gpio_write(bareruby_gpio_t *self, int32_t value) {
          gpio_set_level((gpio_num_t)self->pin, value != 0 ? 1 : 0);
          return 0;
      }

      int32_t bareruby_gpio_read(bareruby_gpio_t *self) {
          return gpio_get_level((gpio_num_t)self->pin) ? 1 : 0;
      }

      bool bareruby_gpio_high(bareruby_gpio_t *self) {
          return gpio_get_level((gpio_num_t)self->pin) != 0;
      }

      bool bareruby_gpio_low(bareruby_gpio_t *self) {
          return gpio_get_level((gpio_num_t)self->pin) == 0;
      }

      /* The events are the one-hot set the class defines: the two levels first, then the
         two edges, and both edges together meaning either. */
      static gpio_int_type_t bareruby_gpio_edge(int32_t events) {
          if ((events & 12) == 12) {
              return GPIO_INTR_ANYEDGE;
          }
          if (events & 8) {
              return GPIO_INTR_POSEDGE;
          }
          if (events & 4) {
              return GPIO_INTR_NEGEDGE;
          }
          return (events & 2) ? GPIO_INTR_HIGH_LEVEL : GPIO_INTR_LOW_LEVEL;
      }

      /* The dispatcher is the driver's and there is one of it, so the first registration
         starts it and every later one joins. Asked twice it says so on the console, which
         is a complaint about this side rather than about the program. */
      static bool bareruby_gpio_dispatching = false;

      void bareruby_gpio_irq(
          bareruby_gpio_t *self, int32_t events, bareruby_interrupt_handler_t handler) {
          bareruby_gpio_interrupt_handler = handler;
          if (!bareruby_gpio_dispatching) {
              bareruby_gpio_dispatching = true;
              gpio_install_isr_service(0);
          }
          gpio_set_intr_type((gpio_num_t)self->pin, bareruby_gpio_edge(events));
          gpio_isr_handler_add((gpio_num_t)self->pin, bareruby_gpio_interrupt_callback, NULL);
          gpio_intr_enable((gpio_num_t)self->pin);
      }
    CPP

    # A serial line. **The receive queue is the driver's**, which is the one place this
    # binding differs from a board whose ring it owns: this driver will not send without
    # one, so the queue is bought by opening the line rather than by reading from it.
    UART = <<~CPP
      #include "bareruby_binding.h"

      #include <stdarg.h>
      #include <stdio.h>
      #include <string.h>

      #include "driver/gpio.h"
      #include "driver/uart.h"
      #include "freertos/FreeRTOS.h"
      #include "freertos/task.h"

      /* What this binding gives when the program did not ask. A program that asks reaches
         the same name from the header, settled where the call was written.

         **A size this driver will not take is refused rather than substituted.** It will
         not hold a queue smaller than the hardware FIFO it drains, and a program that
         asked for 64 bytes and silently got 129 has been told something untrue about the
         board it is running on. The build stops here instead, where the number is. */
      #ifndef BARERUBY_UART_RX_BUFFER_SIZE
      #define BARERUBY_UART_RX_BUFFER_SIZE 256
      #else
      #if BARERUBY_UART_RX_BUFFER_SIZE <= 128
      #error "rx_buffer_size: this driver will not hold a queue smaller than the hardware FIFO it drains, which is 128 bytes"
      #endif
      #endif

      static uart_port_t bareruby_uart_port(const bareruby_uart_t *self) {
          return (uart_port_t)self->unit;
      }

      /* **A pin that was not asked for is the one this board brought the line out on**,
         and which pin that is arrives as a definition from the board rather than as a
         number written here. */
      static int32_t bareruby_uart_txd(const bareruby_uart_t *self) {
          if (self->txd_pin >= 0) {
              return self->txd_pin;
          }
          return self->unit == 0 ? BARERUBY_UART0_TXD_PIN : BARERUBY_UART1_TXD_PIN;
      }

      static int32_t bareruby_uart_rxd(const bareruby_uart_t *self) {
          if (self->rxd_pin >= 0) {
              return self->rxd_pin;
          }
          return self->unit == 0 ? BARERUBY_UART0_RXD_PIN : BARERUBY_UART1_RXD_PIN;
      }

      /* Flow control takes two more pins, and a line without it takes neither — so these
         two are the only ones that can honestly answer "not this one". */
      static int32_t bareruby_uart_flow_pin(int32_t asked, int32_t flow_control) {
          return (flow_control != 0 && asked >= 0) ? asked : UART_PIN_NO_CHANGE;
      }

      static void bareruby_uart_route(const bareruby_uart_t *self) {
          uart_set_pin(bareruby_uart_port(self), bareruby_uart_txd(self), bareruby_uart_rxd(self),
                       bareruby_uart_flow_pin(self->rts_pin, self->flow_control),
                       bareruby_uart_flow_pin(self->cts_pin, self->flow_control));
      }

      /* What the line is opened with, applied. The constructor and setmode differ only in
         where the values came from, so both end here. */
      static void bareruby_uart_apply(bareruby_uart_t *self) {
          uart_port_t port = bareruby_uart_port(self);
          uart_config_t settings = {};
          settings.baud_rate = self->baudrate;
          /* The driver counts data bits from five, so the frame asked for is that many
             fewer than what it is spelled as. */
          settings.data_bits = (uart_word_length_t)(self->data_bits - 5);
          settings.parity = self->parity == 1 ? UART_PARITY_EVEN
                                              : (self->parity == 2 ? UART_PARITY_ODD
                                                                   : UART_PARITY_DISABLE);
          settings.stop_bits = self->stop_bits == 2 ? UART_STOP_BITS_2 : UART_STOP_BITS_1;
          settings.flow_ctrl = self->flow_control != 0 ? UART_HW_FLOWCTRL_CTS_RTS
                                                       : UART_HW_FLOWCTRL_DISABLE;
          settings.rx_flow_ctrl_thresh = 122;
          settings.source_clk = UART_SCLK_DEFAULT;
          uart_param_config(port, &settings);
          bareruby_uart_route(self);
          if (!uart_is_driver_installed(port)) {
              /* No send queue: a write reaches the wire before it returns, which is what
                 lets bytes_to_write answer about the hardware alone. */
              uart_driver_install(port, BARERUBY_UART_RX_BUFFER_SIZE, 0, 0, NULL, 0);
          }
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
          uart_write_bytes(bareruby_uart_port(self), value, length);
          return (int32_t)length;
      }

      /* **What ends a line is the line's, not the compiler's.** puts puts the ending the
         class was given; write puts nothing after what it was handed, whether or not the
         program wrote an interpolation. */
      void bareruby_uart_puts(bareruby_uart_t *self, const char *value) {
          bareruby_uart_write(self, value);
          uart_write_bytes(bareruby_uart_port(self), self->line_ending,
                           strlen(self->line_ending));
      }

      void bareruby_uart_printf(bareruby_uart_t *self, const char *format, ...) {
          char payload[256];
          va_list arguments;
          va_start(arguments, format);
          vsnprintf(payload, sizeof(payload), format, arguments);
          va_end(arguments);
          bareruby_uart_write(self, payload);
      }

      void bareruby_uart_printf_line(bareruby_uart_t *self, const char *format, ...) {
          char payload[256];
          va_list arguments;
          va_start(arguments, format);
          vsnprintf(payload, sizeof(payload), format, arguments);
          va_end(arguments);
          bareruby_uart_puts(self, payload);
      }

      /* Weak, so the uart_receive unit's answer replaces this one the moment a program
         touches the buffered receive side. The queue is the same one either way — this is
         the depth without the byte a peek is holding back, because nothing has peeked. */
      __attribute__((weak)) int32_t bareruby_uart_bytes_available(bareruby_uart_t *self) {
          size_t held = 0;
          uart_get_buffered_data_len(bareruby_uart_port(self), &held);
          return (int32_t)held;
      }

      /* The driver writes by blocking, so nothing waits behind the call. What can still be
         owed is what the transmit FIFO holds, which is what a zero-length wait asks. */
      int32_t bareruby_uart_bytes_to_write(bareruby_uart_t *self) {
          return uart_wait_tx_done(bareruby_uart_port(self), 0) == ESP_OK ? 0 : 1;
      }

      /* **A break is the line held low for longer than a frame**, and this driver only
         offers one after a payload it is sending. So the pin is taken back for the span
         asked for and handed to the line again afterwards, which serves the span exactly
         and puts nothing on the wire that the program did not write. */
      void bareruby_uart_break(bareruby_uart_t *self, int32_t milliseconds) {
          uart_port_t port = bareruby_uart_port(self);
          uart_wait_tx_done(port, portMAX_DELAY);
          gpio_num_t pin = (gpio_num_t)bareruby_uart_txd(self);
          gpio_set_direction(pin, GPIO_MODE_OUTPUT);
          gpio_set_level(pin, 0);
          vTaskDelay(pdMS_TO_TICKS(milliseconds > 0 ? milliseconds : 0));
          gpio_set_level(pin, 1);
          bareruby_uart_route(self);
      }

      void bareruby_uart_flush(bareruby_uart_t *self) {
          uart_wait_tx_done(bareruby_uart_port(self), portMAX_DELAY);
      }

      /* Weak for the same reason as bytes_available: once a peek can be holding a byte
         back, emptying the queue has to empty that too. */
      __attribute__((weak)) void bareruby_uart_clear_rx_buffer(bareruby_uart_t *self) {
          uart_flush_input(bareruby_uart_port(self));
      }

      /* Nothing is held back on the way out, so there is nothing to discard — what is
         left is what the hardware is still shifting, and that is waited for. */
      void bareruby_uart_clear_tx_buffer(bareruby_uart_t *self) {
          uart_wait_tx_done(bareruby_uart_port(self), portMAX_DELAY);
      }
    CPP

    # The buffered receive side. **The queue was bought by opening the line**, because this
    # driver will not send without one — so what this unit adds is not the queue but the
    # one byte a peek has to hold back: the driver takes a byte off its ring and cannot put
    # it back, and looking at what is next without taking it is the whole of the difference.
    UART_RECEIVE = <<~CPP
      #include "bareruby_binding.h"

      #include "driver/uart.h"

      static uart_port_t bareruby_uart_receive_port(const bareruby_uart_t *self) {
          return (uart_port_t)self->unit;
      }

      /* The one byte outside the driver's ring, and -1 for holding none. One line is
         peeked at a time here, which is the same one queue every other call reaches. */
      static int32_t bareruby_uart_peeked = -1;

      int32_t bareruby_uart_getbyte(bareruby_uart_t *self) {
          if (bareruby_uart_peeked >= 0) {
              int32_t byte = bareruby_uart_peeked;
              bareruby_uart_peeked = -1;
              return byte;
          }
          uint8_t byte = 0;
          int received = uart_read_bytes(bareruby_uart_receive_port(self), &byte, 1, 0);
          return received == 1 ? (int32_t)byte : -1;
      }

      int32_t bareruby_uart_peek(bareruby_uart_t *self) {
          if (bareruby_uart_peeked < 0) {
              bareruby_uart_peeked = bareruby_uart_getbyte(self);
          }
          return bareruby_uart_peeked;
      }

      /* The strong definitions; the polling ones in the uart unit are weak. What a peek is
         holding is still in the queue as far as anyone asking is concerned. */
      int32_t bareruby_uart_bytes_available(bareruby_uart_t *self) {
          size_t held = 0;
          uart_get_buffered_data_len(bareruby_uart_receive_port(self), &held);
          return (int32_t)held + (bareruby_uart_peeked >= 0 ? 1 : 0);
      }

      void bareruby_uart_clear_rx_buffer(bareruby_uart_t *self) {
          bareruby_uart_peeked = -1;
          uart_flush_input(bareruby_uart_receive_port(self));
      }
    CPP

    # The receive notification. The driver's own interrupt is what fills the queue; every
    # policy — what a line is, the cap, the discard, the handler itself — runs in thread
    # mode when a wait drains it.
    UART_INTERRUPT = <<~CPP
      #include "bareruby_binding.h"

      #include <stddef.h>

      /* **The notification says which port and which event, and stops there.** What
         arrived is in the queue, and the handler takes it with the same call a program
         would; nothing here knows what a line is. The registration is remembered rather
         than handed to the driver, because the handler runs in thread mode — a wait is
         where it gets to run, and a wait is where the drain below is called from. */
      static bareruby_uart_irq_handler_t bareruby_uart_irq_handler;
      static bareruby_uart_t *bareruby_uart_irq_port;
      static int32_t bareruby_uart_irq_events;

      void bareruby_uart_irq(
          bareruby_uart_t *self, int32_t events, bareruby_uart_irq_handler_t handler) {
          bareruby_uart_irq_handler = handler;
          bareruby_uart_irq_port = self;
          bareruby_uart_irq_events = events;
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

    # A pin driven as a square wave. The LED controller counts a period in ticks of the
    # clock it is given, so how finely a period can be divided is decided by how long it
    # is — which is why the number of ticks a duty is out of is worked out from the
    # frequency every time rather than kept.
    PWM = <<~CPP
      #include "bareruby_binding.h"

      #include "driver/ledc.h"

      /* The clock the low-speed timers count. Every division below is against it. */
      #define BARERUBY_LEDC_CLOCK 80000000ULL

      static uint32_t bareruby_ledc_bits(int32_t frequency) {
          uint32_t bits = LEDC_TIMER_14_BIT;
          while (bits > 1 && ((uint64_t)frequency << bits) > BARERUBY_LEDC_CLOCK) {
              --bits;
          }
          return bits;
      }

      static uint32_t bareruby_ledc_top(const bareruby_pwm_t *self) {
          return (1u << bareruby_ledc_bits(self->frequency)) - 1u;
      }

      /* **A line takes the next channel, and the timer that goes with it.** There are more
         channels than timers, so two lines past the fourth share a timer and so share a
         frequency — which is a limit of the hardware rather than a decision here, and the
         programs this was written for drive one or two lines. */
      static int32_t bareruby_ledc_next = 0;

      static ledc_timer_t bareruby_ledc_timer(const bareruby_pwm_t *self) {
          return (ledc_timer_t)(self->slice % LEDC_TIMER_MAX);
      }

      static ledc_channel_t bareruby_ledc_channel(const bareruby_pwm_t *self) {
          return (ledc_channel_t)self->slice;
      }

      void bareruby_pwm_apply_frequency(bareruby_pwm_t *self, int32_t frequency) {
          self->frequency = frequency;
          if (frequency <= 0) {
              ledc_stop(LEDC_LOW_SPEED_MODE, bareruby_ledc_channel(self), 0);
              return;
          }
          ledc_timer_config_t timer = {};
          timer.speed_mode = LEDC_LOW_SPEED_MODE;
          timer.timer_num = bareruby_ledc_timer(self);
          timer.duty_resolution = (ledc_timer_bit_t)bareruby_ledc_bits(frequency);
          timer.freq_hz = (uint32_t)frequency;
          timer.clk_cfg = LEDC_AUTO_CLK;
          ledc_timer_config(&timer);
      }

      static void bareruby_pwm_level(bareruby_pwm_t *self, uint32_t ticks) {
          ledc_set_duty(LEDC_LOW_SPEED_MODE, bareruby_ledc_channel(self), ticks);
          ledc_update_duty(LEDC_LOW_SPEED_MODE, bareruby_ledc_channel(self));
      }

      void bareruby_pwm_apply_duty(bareruby_pwm_t *self, int32_t duty) {
          uint32_t top = bareruby_ledc_top(self);
          bareruby_pwm_level(self, duty > 0 ? (uint32_t)((uint64_t)top * (uint64_t)duty / 100u) : 0u);
      }

      /* A pulse width is a duty once the period is known, and the period is the frequency
         the line is running at. */
      void bareruby_pwm_apply_pulse_width_us(bareruby_pwm_t *self, int32_t pulse_width_us) {
          uint64_t top = (uint64_t)bareruby_ledc_top(self) + 1u;
          uint64_t ticks = (uint64_t)(pulse_width_us > 0 ? pulse_width_us : 0) *
                           (uint64_t)self->frequency * top / 1000000u;
          bareruby_pwm_level(self, (uint32_t)ticks);
      }

      void bareruby_pwm_apply_period_us(bareruby_pwm_t *self, int32_t period_us) {
          bareruby_pwm_apply_frequency(self, period_us > 0 ? (int32_t)(1000000 / period_us) : 0);
      }

      void bareruby_pwm_init(bareruby_pwm_t *self, int32_t pin, int32_t frequency, int32_t duty) {
          self->pin = pin;
          self->slice = bareruby_ledc_next++;
          bareruby_pwm_apply_frequency(self, frequency);
          ledc_channel_config_t channel = {};
          channel.gpio_num = (int)pin;
          channel.speed_mode = LEDC_LOW_SPEED_MODE;
          channel.channel = bareruby_ledc_channel(self);
          channel.timer_sel = bareruby_ledc_timer(self);
          channel.intr_type = LEDC_INTR_DISABLE;
          channel.duty = 0;
          channel.hpoint = 0;
          ledc_channel_config(&channel);
          bareruby_pwm_apply_duty(self, duty);
      }
    CPP

    # A pin read as a voltage. One converter answers every line here, so the first pin
    # named brings it up and the rest join it.
    ADC = <<~CPP
      #include "bareruby_binding.h"

      #include <stddef.h>

      #include "esp_adc/adc_oneshot.h"

      static adc_oneshot_unit_handle_t bareruby_adc_unit;

      void bareruby_adc_init(bareruby_adc_t *self, int32_t pin) {
          self->pin = pin;
          /* The first converter's channels are this chip's first ten pins, in order. */
          self->channel = pin - 1;
          if (bareruby_adc_unit == NULL) {
              adc_oneshot_unit_init_cfg_t unit = {};
              unit.unit_id = ADC_UNIT_1;
              adc_oneshot_new_unit(&unit, &bareruby_adc_unit);
          }
          adc_oneshot_chan_cfg_t channel = {};
          /* The widest attenuation, which is what reads a line that swings to the supply.
             It is also the least linear, and nothing here corrects for that. */
          channel.atten = ADC_ATTEN_DB_12;
          channel.bitwidth = ADC_BITWIDTH_DEFAULT;
          adc_oneshot_config_channel(bareruby_adc_unit, (adc_channel_t)self->channel, &channel);
      }

      int32_t bareruby_adc_read_raw(bareruby_adc_t *self) {
          int value = 0;
          adc_oneshot_read(bareruby_adc_unit, (adc_channel_t)self->channel, &value);
          return (int32_t)value;
      }

      /* Twelve bits over the 3.1 V this attenuation reaches, in Q16.16. */
      int32_t bareruby_adc_read(bareruby_adc_t *self) {
          int64_t raw = (int64_t)bareruby_adc_read_raw(self);
          return (int32_t)((raw * 3100 * 65536) / (4095 * 1000));
      }
    CPP

    # The I2C bus. **A device rather than a bus is what this driver is spoken to through**,
    # so each transaction adds the address it is for and takes it away again — which is
    # what lets one bus object in Ruby address as many devices as the program names.
    I2C = <<~CPP
      #include "bareruby_binding.h"

      #include <stddef.h>

      #include "driver/i2c_master.h"

      #define BARERUBY_I2C_TIMEOUT_MS 1000

      static int32_t bareruby_i2c_sda_pin(int32_t unit) {
          return unit == 0 ? BARERUBY_I2C0_SDA_PIN : BARERUBY_I2C1_SDA_PIN;
      }

      static int32_t bareruby_i2c_scl_pin(int32_t unit) {
          return unit == 0 ? BARERUBY_I2C0_SCL_PIN : BARERUBY_I2C1_SCL_PIN;
      }

      /* **The bus is asked for by port rather than kept here.** The read side is a
         translation unit of its own and needs the same bus; asking the driver which bus
         that port is leaves one answer instead of two that have to agree. */
      static i2c_master_bus_handle_t bareruby_i2c_bus(int32_t unit) {
          i2c_master_bus_handle_t bus = NULL;
          i2c_master_get_bus_handle((i2c_port_num_t)unit, &bus);
          return bus;
      }

      i2c_master_dev_handle_t bareruby_i2c_device(const bareruby_i2c_t *self, int32_t address) {
          i2c_device_config_t device = {};
          device.dev_addr_length = I2C_ADDR_BIT_LEN_7;
          device.device_address = (uint16_t)address;
          device.scl_speed_hz = (uint32_t)self->frequency;
          i2c_master_dev_handle_t handle = NULL;
          i2c_master_bus_add_device(bareruby_i2c_bus(self->unit), &device, &handle);
          return handle;
      }

      void bareruby_i2c_init(bareruby_i2c_t *self, int32_t unit, int32_t frequency) {
          self->unit = unit;
          self->frequency = frequency;
          if (bareruby_i2c_bus(unit) != NULL) {
              return;
          }
          i2c_master_bus_config_t bus = {};
          bus.i2c_port = (i2c_port_num_t)unit;
          bus.sda_io_num = (gpio_num_t)bareruby_i2c_sda_pin(unit);
          bus.scl_io_num = (gpio_num_t)bareruby_i2c_scl_pin(unit);
          bus.clk_source = I2C_CLK_SRC_DEFAULT;
          bus.glitch_ignore_cnt = 7;
          bus.flags.enable_internal_pullup = true;
          i2c_master_bus_handle_t handle = NULL;
          i2c_new_master_bus(&bus, &handle);
      }

      int32_t bareruby_i2c_write(
          bareruby_i2c_t *self, int32_t address, const char *bytes, int32_t length) {
          i2c_master_dev_handle_t device = bareruby_i2c_device(self, address);
          esp_err_t answered = i2c_master_transmit(device, (const uint8_t *)bytes, (size_t)length,
                                                   BARERUBY_I2C_TIMEOUT_MS);
          i2c_master_bus_rm_device(device);
          return answered == ESP_OK ? length : -1;
      }
    CPP

    I2C_READ = <<~CPP
      #include "bareruby_binding.h"

      #include <stddef.h>

      #include "driver/i2c_master.h"

      #define BARERUBY_I2C_READ_TIMEOUT_MS 1000

      i2c_master_dev_handle_t bareruby_i2c_device(const bareruby_i2c_t *self, int32_t address);

      /* **What the program wrote before reading goes out in the same transaction.** A
         register is named and then read back without letting the bus go, which is what
         this driver's combined transfer is for; with nothing to say first, it is a plain
         read. */
      bareruby_string_t *bareruby_i2c_read(
          bareruby_i2c_t *self, bareruby_arena_t *arena, int32_t address, int32_t length,
          const char *outputs, int32_t output_length) {
          i2c_master_dev_handle_t device = bareruby_i2c_device(self, address);
          uint8_t bytes[length];
          esp_err_t answered;
          if (0 < output_length) {
              answered = i2c_master_transmit_receive(
                  device, (const uint8_t *)outputs, (size_t)output_length, bytes, (size_t)length,
                  BARERUBY_I2C_READ_TIMEOUT_MS);
          } else {
              answered = i2c_master_receive(device, bytes, (size_t)length,
                                            BARERUBY_I2C_READ_TIMEOUT_MS);
          }
          i2c_master_bus_rm_device(device);
          bareruby_string_t *result = bareruby_string_new(arena, "");
          if (answered == ESP_OK) {
              for (int32_t index = 0; index < length; ++index) {
                  bareruby_string_append_byte(result, bytes[index]);
              }
          }
          return result;
      }
    CPP

    # **The indicator on this family of boards is a device on a wire, not a pin.** One
    # WS2812 takes twenty-four bits of colour in a stream whose bit period is 1.25 us and
    # whose high time says which bit it is — timing no loop of stores can keep — so it is
    # handed to the transmitter that exists for exactly this, counting in tenths of a
    # microsecond so that both halves of a bit are whole numbers of ticks.
    ONBOARD_LED_RGB = <<~CPP
      #include "bareruby_binding.h"

      #include "driver/rmt_tx.h"

      /* Ticks per second, which makes one tick 0.1 us: a bit is 3 ticks against 9, or 9
         against 3, and a period is the twelve of them the device asks for. */
      #define BARERUBY_LED_RESOLUTION 10000000

      /* **An indicator answers on or off, and this one takes a colour** — so "on" is a
         level of white low enough to be looked at rather than the full scale that makes
         one of these painful. */
      #define BARERUBY_LED_ON 32

      static rmt_channel_handle_t bareruby_led_channel;
      static rmt_encoder_handle_t bareruby_led_encoder;

      void bareruby_onboard_led_write(bareruby_onboard_led_t *self, int32_t value) {
          self->state = (value != 0) ? 1 : 0;
          uint8_t level = self->state ? BARERUBY_LED_ON : 0;
          /* Green first: this device takes its three bytes in that order. */
          uint8_t colour[3] = { level, level, level };
          rmt_transmit_config_t transmission = {};
          rmt_transmit(bareruby_led_channel, bareruby_led_encoder, colour, sizeof(colour),
                       &transmission);
          rmt_tx_wait_all_done(bareruby_led_channel, -1);
      }

      void bareruby_onboard_led_init(bareruby_onboard_led_t *self) {
          rmt_tx_channel_config_t channel = {};
          channel.gpio_num = (gpio_num_t)BARERUBY_ONBOARD_LED_PIN;
          channel.clk_src = RMT_CLK_SRC_DEFAULT;
          channel.resolution_hz = BARERUBY_LED_RESOLUTION;
          channel.mem_block_symbols = 64;
          channel.trans_queue_depth = 4;
          rmt_new_tx_channel(&channel, &bareruby_led_channel);

          rmt_bytes_encoder_config_t encoder = {};
          encoder.bit0.level0 = 1;
          encoder.bit0.duration0 = 3;
          encoder.bit0.level1 = 0;
          encoder.bit0.duration1 = 9;
          encoder.bit1.level0 = 1;
          encoder.bit1.duration0 = 9;
          encoder.bit1.level1 = 0;
          encoder.bit1.duration1 = 3;
          encoder.flags.msb_first = 1;
          rmt_new_bytes_encoder(&encoder, &bareruby_led_encoder);

          rmt_enable(bareruby_led_channel);
          bareruby_onboard_led_write(self, 0);
      }

      void bareruby_onboard_led_on(bareruby_onboard_led_t *self) {
          bareruby_onboard_led_write(self, 1);
      }

      void bareruby_onboard_led_off(bareruby_onboard_led_t *self) {
          bareruby_onboard_led_write(self, 0);
      }
    CPP

    PWM_FILE = "bareruby_binding_pwm_esp_idf.cpp"
    ADC_FILE = "bareruby_binding_adc_esp_idf.cpp"
    UART_FILE = "bareruby_binding_uart_esp_idf.cpp"
    GPIO_FILE = "bareruby_binding_gpio_esp_idf.cpp"
    PERIPHERAL_FILE = "bareruby_binding_esp_idf.cpp"
    UART_RECEIVE_FILE = "bareruby_binding_uart_receive_esp_idf.cpp"
    UART_INTERRUPT_FILE = "bareruby_binding_uart_interrupt_esp_idf.cpp"
    I2C_FILE = "bareruby_binding_i2c_esp_idf.cpp"
    I2C_READ_FILE = "bareruby_binding_i2c_read_esp_idf.cpp"
    ONBOARD_LED_RGB_FILE = "bareruby_binding_onboard_led_esp_idf_rgb.cpp"

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
      ONBOARD_LED_RGB_FILE => ONBOARD_LED_RGB
    }.freeze

    # What a peripheral asks for by key, this binding answers with a file. The key is the
    # peripheral's word and the file is this side's, so neither has to know the other.
    UNITS = { onboard_led: :onboard_led_file, gpio: GPIO_FILE, adc: ADC_FILE, uart: UART_FILE,
              uart_receive: UART_RECEIVE_FILE, uart_interrupt: UART_INTERRUPT_FILE,
              pwm: PWM_FILE, i2c: I2C_FILE, i2c_read: I2C_READ_FILE }.freeze

    # A unit is usually one file. **Some are the machine's answer instead** — an indicator
    # is one pin on one board of this family and a device on a wire on another, so the key
    # resolves to a question rather than a name, and the cell beside this file answers it.
    def self.unit(key, machine)
      found = UNITS.fetch(key)
      found.is_a?(Symbol) ? machine(machine).public_send(found) : found
    end

    ALWAYS = [PERIPHERAL_FILE].freeze

    # What a machine takes is not worked out here. Each machine this binding reaches writes
    # its own answer as a method, in machine/ beside this file, and this only hands the
    # question over. A machine it cannot reach has no answer rather than a wrong one.
    MACHINES = {}

    def self.machine(machine) = MACHINES.fetch(machine.key)

    # FreeRTOS owns main and calls into the program, so this side names no entry point and
    # the program's translation unit is named after the program.
    PROGRAM_FILE = "bareruby_program.cpp"

    def self.key = :esp_idf

    def self.toolchain = EspIdfToolchain

    def self.tools = EspIdfTools

    def self.flash = EspIdfFlash

    def self.build = EspIdfBuild
  end
end

# One machine to a file, so that teaching this binding a new machine is adding a file.
Dir.children(File.expand_path("machine", __dir__)).sort.grep(/\.rb\z/).each do |entry|
  require_relative "machine/#{entry}"
end
