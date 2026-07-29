# frozen_string_literal: true

module BareRubyProt
  module Pass
    class CppSourceGenerator
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

          typedef struct {
              int32_t pin;
              int32_t params;
          } bareruby_gpio_t;

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
              int32_t id;
              int32_t frequency;
          } bareruby_i2c_t;

          typedef struct {
              int32_t pin;
              int32_t channel;
          } bareruby_adc_t;

          void bareruby_startup(void);

          void bareruby_gpio_init(bareruby_gpio_t *self, int32_t pin, int32_t params);
          void bareruby_gpio_write(bareruby_gpio_t *self, int32_t value);
          int32_t bareruby_gpio_read(bareruby_gpio_t *self);
          bool bareruby_gpio_high(bareruby_gpio_t *self);
          bool bareruby_gpio_low(bareruby_gpio_t *self);
          void bareruby_gpio_on_interrupt(
              bareruby_gpio_t *self, int32_t events, bareruby_interrupt_handler_t handler);

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

          void bareruby_i2c_init(bareruby_i2c_t *self, int32_t id, int32_t frequency);
          int32_t bareruby_i2c_write(
              bareruby_i2c_t *self, int32_t address, const char *bytes, int32_t length);
          bareruby_string_t *bareruby_i2c_read(
              bareruby_i2c_t *self, bareruby_arena_t *arena, int32_t address, int32_t length,
              const char *outputs, int32_t output_length);

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
      end
    end
  end
end
