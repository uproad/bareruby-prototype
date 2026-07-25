#ifndef BARERUBY_BINDING_H
#define BARERUBY_BINDING_H

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int32_t pin;
    int32_t params;
} bareruby_gpio_t;

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

void bareruby_startup(void);

void bareruby_gpio_init(bareruby_gpio_t *self, int32_t pin, int32_t params);
void bareruby_gpio_write(bareruby_gpio_t *self, int32_t value);
int32_t bareruby_gpio_read(bareruby_gpio_t *self);
bool bareruby_gpio_high(bareruby_gpio_t *self);
bool bareruby_gpio_low(bareruby_gpio_t *self);

void bareruby_pwm_init(bareruby_pwm_t *self, int32_t pin, int32_t frequency, int32_t duty);
void bareruby_pwm_frequency(bareruby_pwm_t *self, int32_t frequency);
void bareruby_pwm_period_us(bareruby_pwm_t *self, int32_t period_us);
void bareruby_pwm_duty(bareruby_pwm_t *self, int32_t duty);
void bareruby_pwm_pulse_width_us(bareruby_pwm_t *self, int32_t pulse_width_us);

void bareruby_uart_init(bareruby_uart_t *self, int32_t id, int32_t baud, int32_t parity);
int32_t bareruby_uart_write(bareruby_uart_t *self, const char *value);
void bareruby_uart_puts(bareruby_uart_t *self, const char *value);
void bareruby_uart_printf(bareruby_uart_t *self, const char *format, ...);
int32_t bareruby_uart_bytes_available(bareruby_uart_t *self);
bool bareruby_uart_can_read_line(bareruby_uart_t *self);
void bareruby_uart_flush(bareruby_uart_t *self);
void bareruby_uart_clear_rx_buffer(bareruby_uart_t *self);
void bareruby_uart_clear_tx_buffer(bareruby_uart_t *self);

void bareruby_machine_delay_us(int32_t microseconds);
void bareruby_sleep(int32_t seconds);
void bareruby_sleep_ms(int32_t milliseconds);

#ifdef __cplusplus
}
#endif

#endif
