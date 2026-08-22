# frozen_string_literal: true

require "bareruby_prot/peripheral"

# A pin driven as a square wave, as a class a program may name. Everything the compiler
# learns about it is here: what may be said to it, what those calls lower to, what the
# generated C++ must declare, and which translation unit a binding has to supply once it
# is reached.
#
# **Not every binding has one.** A NUCLEO board reached through the STM32Cube HAL answers
# no PWM call, and says so by having no file for this key rather than by an entry that
# leads nowhere.
module BareRubyProt
  Peripheral.register(
    :PWM,
    struct: :bareruby_pwm_t,
    constants: {},
    constructor: {
      function: :bareruby_pwm_init,
      parameter_types: %i[Int32],
      keywords: { frequency: 0, duty: 0 }
    },
    # **Each of these answers the setting it just applied.** Two answer the frequency and
    # two answer the duty, because that is what asking for a period or a pulse width comes
    # to. They are `Fixed` where PicoRuby answers `Float`, for the reason every fraction
    # here is.
    methods: {
      frequency: { function: :bareruby_pwm_frequency, parameter_types: %i[Int32], return_type: :Fixed },
      period_us: { function: :bareruby_pwm_period_us, parameter_types: %i[Int32], return_type: :Fixed },
      duty: { function: :bareruby_pwm_duty, parameter_types: %i[Int32], return_type: :Fixed },
      pulse_width_us: {
        function: :bareruby_pwm_pulse_width_us, parameter_types: %i[Int32], return_type: :Fixed
      }
    },
    required_name: "pwm",
    declaration: <<~CPP.chomp,
      typedef struct {
          int32_t pin;
          int32_t slice;
          int32_t frequency;
      } bareruby_pwm_t;

      void bareruby_pwm_init(bareruby_pwm_t *self, int32_t pin, int32_t frequency, int32_t duty);
      void bareruby_pwm_apply_frequency(bareruby_pwm_t *self, int32_t frequency);
      void bareruby_pwm_apply_period_us(bareruby_pwm_t *self, int32_t period_us);
      void bareruby_pwm_apply_duty(bareruby_pwm_t *self, int32_t duty);
      void bareruby_pwm_apply_pulse_width_us(bareruby_pwm_t *self, int32_t pulse_width_us);

      /* **What these calls answer is arithmetic, not hardware.** Each answers the setting
         it just applied as a Q16.16 fraction — asking for a period is asking for a
         frequency, and asking for a pulse width is asking for a duty — and none of that
         is a question a board is in a position to answer differently. So it is worked out
         here, once, and each binding is left with the applying. */
      static inline int32_t bareruby_pwm_frequency(bareruby_pwm_t *self, int32_t frequency) {
          bareruby_pwm_apply_frequency(self, frequency);
          self->frequency = frequency;
          return (int32_t)((int64_t)frequency << 16);
      }

      static inline int32_t bareruby_pwm_period_us(bareruby_pwm_t *self, int32_t period_us) {
          bareruby_pwm_apply_period_us(self, period_us);
          self->frequency = (int32_t)(1000000 / period_us);
          return (int32_t)(((int64_t)1000000 << 16) / period_us);
      }

      static inline int32_t bareruby_pwm_duty(bareruby_pwm_t *self, int32_t duty) {
          bareruby_pwm_apply_duty(self, duty);
          return (int32_t)((int64_t)duty << 16);
      }

      /* A pulse width is a duty once the period is known, which is why this one reads the
         frequency the struct is carrying. */
      static inline int32_t bareruby_pwm_pulse_width_us(
          bareruby_pwm_t *self, int32_t pulse_width_us) {
          bareruby_pwm_apply_pulse_width_us(self, pulse_width_us);
          return (int32_t)((((int64_t)pulse_width_us * self->frequency) << 16) / 10000);
      }
    CPP
    units: {
      pwm: %i[bareruby_pwm_init bareruby_pwm_frequency bareruby_pwm_period_us
              bareruby_pwm_duty bareruby_pwm_pulse_width_us]
    }
  )
end
