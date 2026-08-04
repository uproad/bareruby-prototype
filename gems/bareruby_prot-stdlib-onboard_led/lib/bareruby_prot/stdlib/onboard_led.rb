# frozen_string_literal: true

require "bareruby_prot/peripheral"

# The indicator a board carries, as a class a program may name. It is deliberately not a
# GPIO with a known pin: on a board that has one it is frequently not a GPIO at all — a
# Pico W drives its through the wireless chip, and GP25, where the plain Pico's LED sits,
# is that chip's select line instead.
#
# **Its unit is the machine's answer rather than a file name.** Every other class here asks
# a binding for a file; this one asks a binding which file *this machine* uses, and the cell
# where the machine and the binding meet says. A program that blinks says nothing about the
# board it will run on.
module BareRubyProt
  Peripheral.register(
    :OnboardLED,
    struct: :bareruby_onboard_led_t,
    constants: {},
    constructor: { function: :bareruby_onboard_led_init, parameter_types: [] },
    methods: {
      write: { function: :bareruby_onboard_led_write, parameter_types: %i[Int32], return_type: :Nil },
      on: { function: :bareruby_onboard_led_on, parameter_types: [], return_type: :Nil },
      off: { function: :bareruby_onboard_led_off, parameter_types: [], return_type: :Nil }
    },
    declaration: <<~CPP.chomp,
      /* The on-board LED has nothing the program needs to carry: where it is and how it
         is driven belong to the board, which the binding already knows. The struct
         exists so the instance has storage like every other peripheral. */
      typedef struct {
          int32_t state;
      } bareruby_onboard_led_t;

      void bareruby_onboard_led_init(bareruby_onboard_led_t *self);
      void bareruby_onboard_led_write(bareruby_onboard_led_t *self, int32_t value);
      void bareruby_onboard_led_on(bareruby_onboard_led_t *self);
      void bareruby_onboard_led_off(bareruby_onboard_led_t *self);
    CPP
    units: {
      onboard_led: %i[bareruby_onboard_led_init bareruby_onboard_led_write
                      bareruby_onboard_led_on bareruby_onboard_led_off]
    }
  )
end
