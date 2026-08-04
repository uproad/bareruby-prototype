# frozen_string_literal: true

module BareRubyProt
  module BindingDeclaration
    HEADER = <<~CPP
      #ifndef BARERUBY_BINDING_H
      #define BARERUBY_BINDING_H

      #include <stdbool.h>
      #include <stdint.h>
      #include "bareruby_runtime.h"

      #ifdef __cplusplus
      extern "C" {
      #endif

      typedef void (*bareruby_interrupt_handler_t)(void);

      /* The on-board LED has nothing the program needs to carry: where it is and how it
         is driven belong to the board, which the binding already knows. The struct
         exists so the instance has storage like every other peripheral. */
      typedef struct {
          int32_t state;
      } bareruby_onboard_led_t;

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

      void bareruby_onboard_led_init(bareruby_onboard_led_t *self);
      void bareruby_onboard_led_write(bareruby_onboard_led_t *self, int32_t value);
      void bareruby_onboard_led_on(bareruby_onboard_led_t *self);
      void bareruby_onboard_led_off(bareruby_onboard_led_t *self);

      void bareruby_pwm_init(bareruby_pwm_t *self, int32_t pin, int32_t frequency, int32_t duty);
      void bareruby_pwm_frequency(bareruby_pwm_t *self, int32_t frequency);
      void bareruby_pwm_period_us(bareruby_pwm_t *self, int32_t period_us);
      void bareruby_pwm_duty(bareruby_pwm_t *self, int32_t duty);
      void bareruby_pwm_pulse_width_us(bareruby_pwm_t *self, int32_t pulse_width_us);

      void bareruby_uart_init(bareruby_uart_t *self, int32_t id, int32_t baud, int32_t parity);
      int32_t bareruby_uart_write(bareruby_uart_t *self, const char *value);
      void bareruby_uart_puts(bareruby_uart_t *self, const char *value);
      void bareruby_uart_printf(bareruby_uart_t *self, const char *format, ...);
      bareruby_string_t *bareruby_uart_read(
          bareruby_uart_t *self, bareruby_arena_t *arena, int32_t length);
      bareruby_string_t *bareruby_uart_gets(bareruby_uart_t *self, bareruby_arena_t *arena);
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
      void bareruby_asleep(int32_t seconds);
      void bareruby_asleep_ms(int32_t milliseconds);
      void bareruby_asleep_us(int32_t microseconds);

      #ifdef __cplusplus
      }
      #endif

      #endif
    CPP

    HEADER_FILE = "bareruby_binding.h"

    # The declarations a peripheral brought with it go **last**, after everything this side
    # declares. They may use a type named here — a handler's signature does — while nothing
    # here can use a type of theirs, so the order is not a preference but the only one that
    # compiles. The guard opens with `extern "C" {` and closes with `}`, and it is the
    # closing pair that this lands in front of.
    #
    # A peripheral that is not installed declares nothing, and a binding that implements it
    # anyway has nothing to implement against — which is the point: **the header says what
    # this build knows about, and nothing else.**
    CLOSING = /^\#ifdef __cplusplus\n\}\n/

    def self.header
      registered = Peripheral.declarations
      return HEADER if registered.empty?

      HEADER.sub(CLOSING) { |closing| "#{registered.join("\n\n")}\n\n#{closing}" }
    end

    def self.files = { HEADER_FILE => header }
  end
end
