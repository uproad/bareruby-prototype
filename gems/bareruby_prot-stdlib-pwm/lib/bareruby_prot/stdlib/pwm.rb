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
    methods: {
      frequency: { function: :bareruby_pwm_frequency, parameter_types: %i[Int32], return_type: :Nil },
      period_us: { function: :bareruby_pwm_period_us, parameter_types: %i[Int32], return_type: :Nil },
      duty: { function: :bareruby_pwm_duty, parameter_types: %i[Int32], return_type: :Nil },
      pulse_width_us: {
        function: :bareruby_pwm_pulse_width_us, parameter_types: %i[Int32], return_type: :Nil
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
      void bareruby_pwm_frequency(bareruby_pwm_t *self, int32_t frequency);
      void bareruby_pwm_period_us(bareruby_pwm_t *self, int32_t period_us);
      void bareruby_pwm_duty(bareruby_pwm_t *self, int32_t duty);
      void bareruby_pwm_pulse_width_us(bareruby_pwm_t *self, int32_t pulse_width_us);
    CPP
    units: {
      pwm: %i[bareruby_pwm_init bareruby_pwm_frequency bareruby_pwm_period_us
              bareruby_pwm_duty bareruby_pwm_pulse_width_us]
    }
  )
end
