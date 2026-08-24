# frozen_string_literal: true

require "bareruby_prot/peripheral"

# A pin driven as a square wave, as a class a program may name. Everything the compiler
# learns about it is here: what may be said to it, what those calls lower to, what the
# generated C++ must declare, and which translation unit a binding has to supply once it
# is reached.
#
# **Not every binding needs one.** A binding that answers no PWM call says so by having
# no file for this key rather than by an entry that leads nowhere — which was the
# STM32Cube binding's answer until it grew a timer table.
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
    # **Each of these answers the setting it just applied**, in the unit that setting is
    # kept in. Two of them set the frequency — one in hertz and one in microseconds of
    # period — and answer the frequency. The other two set the duty, one of them by way of
    # a pulse width, and answer the duty.
    #
    # **A frequency is whole hertz here.** PicoRuby answers a float; this does not, and
    # says so as a deliberate departure rather than a fraction that was rounded away. A
    # duty is a fraction and stays one — a servo asks for 7.5 per cent.
    methods: {
      frequency: { function: :bareruby_pwm_frequency, parameter_types: %i[Int32], return_type: :Int32 },
      period_us: { function: :bareruby_pwm_period_us, parameter_types: %i[Int32], return_type: :Int32 },
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
         it just applied — asking for a period is asking for a frequency, and asking for a
         pulse width is asking for a duty — and none of that is a question a board is in a
         position to answer differently. So it is worked out here, once, and each binding
         is left with the applying.

         **The frequency answered is the one that was set**, in whole hertz, which is what
         the slice was actually given. Answering a fraction of a hertz would name a rate
         nothing on the pin is running at. */
      static inline int32_t bareruby_pwm_frequency(bareruby_pwm_t *self, int32_t frequency) {
          bareruby_pwm_apply_frequency(self, frequency);
          self->frequency = frequency;
          return frequency;
      }

      static inline int32_t bareruby_pwm_period_us(bareruby_pwm_t *self, int32_t period_us) {
          bareruby_pwm_apply_period_us(self, period_us);
          self->frequency = (int32_t)(1000000 / period_us);
          return self->frequency;
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
