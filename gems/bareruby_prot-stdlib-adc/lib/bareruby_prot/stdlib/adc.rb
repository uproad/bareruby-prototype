# frozen_string_literal: true

require "bareruby_prot/peripheral"

# A pin read as a voltage, as a class a program may name. Everything the compiler learns
# about it is here: what may be said to it, what those calls lower to, what the generated
# C++ must declare, and which translation unit a binding has to supply once it is reached.
#
# `read` and `read_voltage` answer `Fixed` where the standard guideline says Float, because
# Fixed is the fractional type here. Q16.16 resolves to 1/65536 V, finer than the least
# significant bit of a 12-bit converter.
module BareRubyProt
  Peripheral.register(
    :ADC,
struct: :bareruby_adc_t,
      constants: {},
      constructor: { function: :bareruby_adc_init, parameter_types: %i[Int32] },
      methods: {
        read: { function: :bareruby_adc_read, parameter_types: [], return_type: :Fixed },
        read_voltage: { function: :bareruby_adc_read, parameter_types: [], return_type: :Fixed },
        read_raw: { function: :bareruby_adc_read_raw, parameter_types: [], return_type: :Int32 }
      },
    required_name: "adc",
    declaration: <<~CPP.chomp,
      typedef struct {
          int32_t pin;
          int32_t channel;
      } bareruby_adc_t;

      void bareruby_adc_init(bareruby_adc_t *self, int32_t pin);
      int32_t bareruby_adc_read(bareruby_adc_t *self);
      int32_t bareruby_adc_read_raw(bareruby_adc_t *self);
    CPP
    units: {
      adc: %i[bareruby_adc_init bareruby_adc_read bareruby_adc_read_raw]
    }
  )
end
