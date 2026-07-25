#include <stdbool.h>
#include <stdint.h>

#include "bareruby_binding.h"

static void bareruby_main(void);

static void bareruby_main(void) {
    bareruby_gpio_t temporary_1;
    bareruby_gpio_init(&temporary_1, 25, 1);
    bareruby_gpio_t led = temporary_1;
    while (true) {
        bareruby_gpio_write(&led, 1);
        bareruby_sleep_ms(500);
        bareruby_gpio_write(&led, 0);
        bareruby_sleep_ms(500);
    }
}

int main(void) {
    bareruby_startup();
    bareruby_main();
    for (;;) {
        bareruby_sleep_ms(1000);
    }
}
