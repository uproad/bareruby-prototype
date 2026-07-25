#include "bareruby_binding.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

#include "hardware/clocks.h"
#include "hardware/gpio.h"
#include "hardware/pwm.h"
#include "hardware/uart.h"
#include "pico/stdlib.h"

void bareruby_startup(void) {
    stdio_init_all();
}

void bareruby_gpio_init(bareruby_gpio_t *self, int32_t pin, int32_t params) {
    self->pin = pin;
    self->params = params;
    gpio_init((uint)pin);
    gpio_set_dir((uint)pin, (params & 1) ? GPIO_OUT : GPIO_IN);
    if (params & 4) {
        gpio_pull_up((uint)pin);
    }
    if (params & 8) {
        gpio_pull_down((uint)pin);
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
    uart_putc(bareruby_uart_port(self), '\n');
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

void bareruby_machine_delay_us(int32_t microseconds) {
    sleep_us((uint64_t)microseconds);
}

void bareruby_sleep(int32_t seconds) {
    sleep_ms((uint32_t)seconds * 1000u);
}

void bareruby_sleep_ms(int32_t milliseconds) {
    sleep_ms((uint32_t)milliseconds);
}
