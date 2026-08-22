# frozen_string_literal: true

require "bareruby_prot/peripheral"

# The I2C bus as a class a program may name. Everything the compiler learns about it is
# here: what may be said to it, what those calls lower to, what the generated C++ must
# declare, and which translation unit a binding has to supply once it is reached.
#
# Nothing on the compiler's side mentions I2C. Uninstall this and a program that says
# `I2C.new(unit: 0)` no longer compiles, while every other program compiles exactly as
# before.
module BareRubyProt
  Peripheral.register(
    :I2C,
    struct: :bareruby_i2c_t,
    constants: {},
    # **Which bus is named, not counted off.** Everything the bus is opened with is a
    # keyword, so that source written against the same class elsewhere opens the same bus
    # here. A unit given by position is a call nobody else's program makes.
    constructor: {
      function: :bareruby_i2c_init,
      parameter_types: [],
      keywords: { unit: 0, frequency: 100_000 }
    },
    # **`payload_from` is where the bytes this call sends begin.** One call in Ruby is one
    # transaction on the wire, so everything from that argument on — integers, strings,
    # arrays, whatever the program had — reaches the bus as one contiguous sequence, and
    # the binding is handed one pointer and one length. It is a fact about this call's
    # shape, so it is said here rather than in a table the compiler keeps: a write sends
    # everything after the address, and a read sends everything after the address and the
    # length it asks for.
    methods: {
      write: {
        function: :bareruby_i2c_write, parameter_types: [], return_type: :Int32, payload_from: 1
      },
      read: {
        function: :bareruby_i2c_read, parameter_types: [], return_type: :arena_string, payload_from: 2
      }
    },

    # `require "i2c"` names no file to find. The class is built in wherever it came from,
    # and saying so is how a program reads the same here as under an interpreter that
    # would have had to load one.
    required_name: "i2c",

    # What the generated C++ must declare for a binding to implement. The header carries
    # this only while this gem is installed.
    declaration: <<~CPP.chomp,
      typedef struct {
          int32_t unit;
          int32_t frequency;
      } bareruby_i2c_t;

      void bareruby_i2c_init(bareruby_i2c_t *self, int32_t unit, int32_t frequency);
      int32_t bareruby_i2c_write(
          bareruby_i2c_t *self, int32_t address, const char *bytes, int32_t length);
      bareruby_string_t *bareruby_i2c_read(
          bareruby_i2c_t *self, bareruby_arena_t *arena, int32_t address, int32_t length,
          const char *outputs, int32_t output_length);
    CPP

    # **Which unit a binding must supply, and how to tell it is needed.** A read pulls in
    # more than a write does — it answers a variable-length string, so it reaches the
    # arena — which is why the two are separate units rather than one.
    units: {
      i2c: %i[bareruby_i2c_init bareruby_i2c_write bareruby_i2c_read],
      i2c_read: %i[bareruby_i2c_read]
    }
  )
end
