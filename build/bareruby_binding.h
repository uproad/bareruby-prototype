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

void bareruby_startup(void);

void bareruby_gpio_init(bareruby_gpio_t *self, int32_t pin, int32_t params);
void bareruby_gpio_write(bareruby_gpio_t *self, int32_t value);
int32_t bareruby_gpio_read(bareruby_gpio_t *self);
bool bareruby_gpio_high(bareruby_gpio_t *self);
bool bareruby_gpio_low(bareruby_gpio_t *self);

void bareruby_sleep(int32_t seconds);
void bareruby_sleep_ms(int32_t milliseconds);

#ifdef __cplusplus
}
#endif

#endif
