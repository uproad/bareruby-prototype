#include <stdbool.h>
#include <stdint.h>

#include "bareruby_binding.h"
#include "bareruby_runtime.h"

struct Servo {
    bareruby_pwm_t pwm;
    int32_t angle;
};

static void Servo_initialize(Servo *self, int32_t pin);
static void Servo_move(Servo *self, int32_t angle);
static void bareruby_main(void);

static void Servo_initialize(Servo *self, int32_t pin) {
    bareruby_pwm_t temporary_1;
    bareruby_pwm_init(&temporary_1, pin, 50, 0);
    self->pwm = temporary_1;
    self->angle = 0;
    return;
}

static void Servo_move(Servo *self, int32_t angle) {
    self->angle = angle;
    bareruby_pwm_pulse_width_us(&self->pwm, (1000 + ((angle * 1000) / 180)));
    return;
}

static void bareruby_main(void) {
    Servo temporary_1;
    Servo_initialize(&temporary_1, 15);
    Servo servo = temporary_1;
    while (true) {
        int32_t temporary_2 = 180;
        for (int32_t angle = 0; (angle <= temporary_2); angle = (angle + 1)) {
            Servo_move(&servo, angle);
            bareruby_machine_delay_us(500);
        }
        bareruby_sleep_ms(300);
    }
}

int main(void) {
    bareruby_startup();
    bareruby_main();
    for (;;) {
        bareruby_sleep_ms(1000);
    }
}
