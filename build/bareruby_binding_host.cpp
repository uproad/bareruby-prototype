#include "bareruby_binding.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

void bareruby_startup(void) {
    fprintf(stderr, "startup()\n");
}

void bareruby_gpio_init(bareruby_gpio_t *self, int32_t pin, int32_t params) {
    self->pin = pin;
    self->params = params;
    fprintf(stderr, "gpio_init(pin=%d, params=%d)\n", (int)pin, (int)params);
}

void bareruby_gpio_write(bareruby_gpio_t *self, int32_t value) {
    fprintf(stderr, "gpio_write(pin=%d, value=%d)\n", (int)self->pin, (int)value);
}

int32_t bareruby_gpio_read(bareruby_gpio_t *self) {
    fprintf(stderr, "gpio_read(pin=%d) -> 0\n", (int)self->pin);
    return 0;
}

bool bareruby_gpio_high(bareruby_gpio_t *self) {
    fprintf(stderr, "gpio_high(pin=%d) -> false\n", (int)self->pin);
    return false;
}

bool bareruby_gpio_low(bareruby_gpio_t *self) {
    fprintf(stderr, "gpio_low(pin=%d) -> true\n", (int)self->pin);
    return true;
}

void bareruby_pwm_init(bareruby_pwm_t *self, int32_t pin, int32_t frequency, int32_t duty) {
    self->pin = pin;
    self->slice = pin / 2;
    self->frequency = frequency;
    fprintf(stderr, "pwm_init(pin=%d, frequency=%d, duty=%d)\n", (int)pin, (int)frequency, (int)duty);
}

void bareruby_pwm_frequency(bareruby_pwm_t *self, int32_t frequency) {
    self->frequency = frequency;
    fprintf(stderr, "pwm_frequency(pin=%d, frequency=%d)\n", (int)self->pin, (int)frequency);
}

void bareruby_pwm_period_us(bareruby_pwm_t *self, int32_t period_us) {
    fprintf(stderr, "pwm_period_us(pin=%d, period_us=%d)\n", (int)self->pin, (int)period_us);
}

void bareruby_pwm_duty(bareruby_pwm_t *self, int32_t duty) {
    fprintf(stderr, "pwm_duty(pin=%d, duty=%d)\n", (int)self->pin, (int)duty);
}

void bareruby_pwm_pulse_width_us(bareruby_pwm_t *self, int32_t pulse_width_us) {
    fprintf(stderr, "pwm_pulse_width_us(pin=%d, pulse_width_us=%d)\n", (int)self->pin, (int)pulse_width_us);
}

static void bareruby_trace_payload(const char *label, const bareruby_uart_t *self, const char *text) {
    fprintf(stderr, "%s(id=%d, text=\"", label, (int)self->id);
    for (const char *cursor = text; *cursor != '\0'; ++cursor) {
        if (*cursor == '\n') {
            fputs("\\n", stderr);
        } else {
            fputc(*cursor, stderr);
        }
    }
    fputs("\")\n", stderr);
}

void bareruby_uart_init(bareruby_uart_t *self, int32_t id, int32_t baud, int32_t parity) {
    self->id = id;
    self->baud = baud;
    self->parity = parity;
    fprintf(stderr, "uart_init(id=%d, baud=%d, parity=%d)\n", (int)id, (int)baud, (int)parity);
}

int32_t bareruby_uart_write(bareruby_uart_t *self, const char *value) {
    bareruby_trace_payload("uart_write", self, value);
    return (int32_t)strlen(value);
}

void bareruby_uart_puts(bareruby_uart_t *self, const char *value) {
    bareruby_trace_payload("uart_puts", self, value);
}

void bareruby_uart_printf(bareruby_uart_t *self, const char *format, ...) {
    char payload[256];
    va_list arguments;
    va_start(arguments, format);
    vsnprintf(payload, sizeof(payload), format, arguments);
    va_end(arguments);
    bareruby_trace_payload("uart_printf", self, payload);
}

int32_t bareruby_uart_bytes_available(bareruby_uart_t *self) {
    fprintf(stderr, "uart_bytes_available(id=%d) -> 0\n", (int)self->id);
    return 0;
}

bool bareruby_uart_can_read_line(bareruby_uart_t *self) {
    fprintf(stderr, "uart_can_read_line(id=%d) -> false\n", (int)self->id);
    return false;
}

void bareruby_uart_flush(bareruby_uart_t *self) {
    fprintf(stderr, "uart_flush(id=%d)\n", (int)self->id);
}

void bareruby_uart_clear_rx_buffer(bareruby_uart_t *self) {
    fprintf(stderr, "uart_clear_rx_buffer(id=%d)\n", (int)self->id);
}

void bareruby_uart_clear_tx_buffer(bareruby_uart_t *self) {
    fprintf(stderr, "uart_clear_tx_buffer(id=%d)\n", (int)self->id);
}

void bareruby_machine_delay_us(int32_t microseconds) {
    fprintf(stderr, "machine_delay_us(microseconds=%d)\n", (int)microseconds);
}

void bareruby_sleep(int32_t seconds) {
    fprintf(stderr, "sleep(seconds=%d)\n", (int)seconds);
}

void bareruby_sleep_ms(int32_t milliseconds) {
    fprintf(stderr, "sleep_ms(milliseconds=%d)\n", (int)milliseconds);
}
