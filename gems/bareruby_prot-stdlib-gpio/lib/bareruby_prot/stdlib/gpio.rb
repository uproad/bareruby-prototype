# frozen_string_literal: true

require "bareruby_prot/peripheral"

# A pin as a class a program may name. Everything the compiler learns about it is here:
# what may be said to it, what those calls lower to, what the generated C++ must declare,
# and which translation unit a binding has to supply once it is reached.
#
# **The interrupt is the part that had to be said rather than assumed.** Its block becomes
# an independent function running in the realtime context, and the compiler used to know
# that by looking for this class and this method by name. It is declared now, so the
# machinery stays the language's while the reason to use it is this gem's.
#
# It is named `irq` and takes the event by position, because that is how every other Ruby
# for microcontrollers spells it. A registration under a name only this implementation
# uses is a registration nobody's existing source can make.
module BareRubyProt
  Peripheral.register(
    :GPIO,
    struct: :bareruby_gpio_t,

    # One-hot, matching PicoRuby, so that directions and pulls combine with | the way the
    # standard guideline spells them.
    constants: {
      IN: 1, OUT: 2, HIGH_Z: 4, PULL_UP: 8, PULL_DOWN: 16, OPEN_DRAIN: 32, EDGE_FALL: 4
    },
    constructor: { function: :bareruby_gpio_init, parameter_types: %i[Int32 Int32] },
    methods: {
      write: { function: :bareruby_gpio_write, parameter_types: %i[Int32], return_type: :Nil },
      read: { function: :bareruby_gpio_read, parameter_types: [], return_type: :Int32 },
      high?: { function: :bareruby_gpio_high, parameter_types: [], return_type: :Bool },
      low?: { function: :bareruby_gpio_low, parameter_types: [], return_type: :Bool },
      irq: {
        function: :bareruby_gpio_irq, parameter_types: %i[Int32], return_type: :Nil,
        block: :realtime_handler
      }
    },
    required_name: "gpio",
    declaration: <<~CPP.chomp,
      typedef struct {
          int32_t pin;
          int32_t params;
      } bareruby_gpio_t;

      void bareruby_gpio_init(bareruby_gpio_t *self, int32_t pin, int32_t params);
      void bareruby_gpio_write(bareruby_gpio_t *self, int32_t value);
      int32_t bareruby_gpio_read(bareruby_gpio_t *self);
      bool bareruby_gpio_high(bareruby_gpio_t *self);
      bool bareruby_gpio_low(bareruby_gpio_t *self);
      void bareruby_gpio_irq(
          bareruby_gpio_t *self, int32_t events, bareruby_interrupt_handler_t handler);
    CPP
    units: {
      gpio: %i[bareruby_gpio_init bareruby_gpio_write bareruby_gpio_read
               bareruby_gpio_high bareruby_gpio_low bareruby_gpio_irq]
    }
  )
end
