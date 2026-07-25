#include "bareruby_binding.h"

#include <stdio.h>

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

void bareruby_sleep(int32_t seconds) {
    fprintf(stderr, "sleep(seconds=%d)\n", (int)seconds);
}

void bareruby_sleep_ms(int32_t milliseconds) {
    fprintf(stderr, "sleep_ms(milliseconds=%d)\n", (int)milliseconds);
}
