#include "bareruby_binding.h"

#include "hardware/gpio.h"
#include "pico/stdlib.h"

void bareruby_startup(void) {
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

void bareruby_sleep(int32_t seconds) {
    sleep_ms((uint32_t)seconds * 1000u);
}

void bareruby_sleep_ms(int32_t milliseconds) {
    sleep_ms((uint32_t)milliseconds);
}
