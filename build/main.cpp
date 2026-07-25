#include <stdint.h>
#include <stdio.h>

static void bareruby_puts_int32(int32_t value);
static void bareruby_puts_int64(int64_t value);

static void bareruby_puts_int32(int32_t value) {
    printf("%d\n", (int)value);
}

static void bareruby_puts_int64(int64_t value) {
    printf("%lld\n", (long long)value);
}

struct Counter {
    int32_t value;
};

static void Counter_initialize(Counter *self, int32_t initial);
static void Counter_reset(Counter *self);
static int32_t Counter_advance(Counter *self, int32_t step, int32_t limit);
static void bareruby_main(void);
static void Counter_initialize(Counter *self, int32_t initial) {
    self->value = initial;
    return;
}

static void Counter_reset(Counter *self) {
    self->value = 0;
    return;
}

static int32_t Counter_advance(Counter *self, int32_t step, int32_t limit) {
    int32_t mask = 7;
    int32_t adjustment = (-step);
    adjustment = (adjustment + 1);
    self->value = (self->value + adjustment);
    int32_t temporary_1 = limit;
    for (int32_t index = 0; (index < temporary_1); index = (index + 1)) {
        self->value = (self->value + index);
        continue;
    }
    int32_t temporary_2 = limit;
    for (int32_t index = 1; (index <= temporary_2); index = (index + 1)) {
        self->value = (self->value << 1);
    }
    while (true) {
        break;
    }
    self->value = (self->value & mask);
    return self->value;
}

static void bareruby_main(void) {
    Counter temporary_1;
    Counter_initialize(&temporary_1, 0);
    Counter counter = temporary_1;
    Counter_reset(&counter);
    int32_t result = Counter_advance(&counter, 1, 2);
    bareruby_puts_int32(result);
}

int main(void) {
    bareruby_main();
    return 0;
}
