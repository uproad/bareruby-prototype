# frozen_string_literal: true

module BareRubyProt
  # One piece of hardware the language offers as a class: what it is called, the struct
  # the binding keeps its state in, the constants it publishes, and the binding functions
  # behind its constructor and its methods. Which implementation those functions have is
  # the second stage's business; what a program may say to them is settled here.
  class Peripheral
    CLASSES = {
    }.freeze

    # The guideline returns a Float from read_voltage, but Fixed is the default
    # fractional type here, so the binding returns Fixed. Q16.16 resolves to 1/65536 V,
    # finer than the 12-bit converter's least significant bit.
    # The on-board LED is its own class rather than a GPIO with a known pin, because on
    # a board that has one it is frequently not a GPIO at all — a Pico W drives its LED
    # through the wireless chip, and GP25, where the plain Pico's LED sits, is that
    # chip's select line instead. Sharing GPIO's interface would only hide that. Which
    # board the program is being built for decides how the binding reaches it, so a
    # program that blinks says nothing about the board it will run on.
    ONBOARD = {
      OnboardLED: {
        struct: :bareruby_onboard_led_t,
        constants: {},
        constructor: { function: :bareruby_onboard_led_init, parameter_types: [] },
        methods: {
          write: { function: :bareruby_onboard_led_write, parameter_types: %i[Int32], return_type: :Nil },
          on: { function: :bareruby_onboard_led_on, parameter_types: [], return_type: :Nil },
          off: { function: :bareruby_onboard_led_off, parameter_types: [], return_type: :Nil }
        }
      }
    }.freeze

    EXTRA = {
      ADC: {
        struct: :bareruby_adc_t,
        constants: {},
        constructor: { function: :bareruby_adc_init, parameter_types: %i[Int32] },
        methods: {
          read: { function: :bareruby_adc_read, parameter_types: [], return_type: :Fixed },
          read_voltage: { function: :bareruby_adc_read, parameter_types: [], return_type: :Fixed },
          read_raw: { function: :bareruby_adc_read_raw, parameter_types: [], return_type: :Int32 }
        }
      },
      UART: {
        struct: :bareruby_uart_t,
        constants: { NONE: 0, EVEN: 1, ODD: 2, RTSCTS: 4 },
        constructor: {
          function: :bareruby_uart_init,
          parameter_types: %i[Int32],
          keywords: { baud: 115_200, parity: 0 }
        },
        methods: {
          # puts and write on a UART take the same printf expansion as the global puts.
          write: {
            function: :bareruby_uart_write, printf_function: :bareruby_uart_printf,
            parameter_types: %i[String], return_type: :Int32
          },
          puts: {
            function: :bareruby_uart_puts, printf_function: :bareruby_uart_printf,
            parameter_types: %i[String], return_type: :Nil
          },
          read: { function: :bareruby_uart_read, parameter_types: %i[Int32], return_type: :arena_string },
          gets: { function: :bareruby_uart_gets, parameter_types: [], return_type: :arena_string },
          bytes_available: {
            function: :bareruby_uart_bytes_available, parameter_types: [], return_type: :Int32
          },
          can_read_line: {
            function: :bareruby_uart_can_read_line, parameter_types: [], return_type: :Bool
          },
          flush: { function: :bareruby_uart_flush, parameter_types: [], return_type: :Nil },
          clear_rx_buffer: {
            function: :bareruby_uart_clear_rx_buffer, parameter_types: [], return_type: :Nil
          },
          clear_tx_buffer: {
            function: :bareruby_uart_clear_tx_buffer, parameter_types: [], return_type: :Nil
          }
        }
      }
    }.freeze

    # sleep waits from the moment it is called, so a loop drifts by however long its
    # body takes. asleep waits from the moment the previous asleep returned, which is
    # what a loop that has to keep a period needs.

    attr_reader :name, :struct, :declaration, :required_name

    def initialize(name, entry)
      @name = name
      @struct = entry[:struct]
      @constants = entry[:constants]
      @constructor = entry[:constructor]
      @methods = entry[:methods]
      @declaration = entry[:declaration]
      @required_name = entry[:required_name]
      @units = entry[:units] || {}
    end

    # **Which translation unit a binding must supply, and how to tell it is needed.** The
    # peripheral names its own C functions, because they are its own; the binding says
    # what file answers a key, because the file is its own. Neither has to know the other
    # to agree, and a peripheral nobody installed asks for nothing.
    def units_reached(low_ir) = @units.select { |_key, functions| low_ir.calls?(*functions) }.keys

    def constant(name) = @constants.fetch(name)

    def constructor_function = @constructor[:function]

    def constructor_keywords = @constructor[:keywords] || {}

    def method_signature(name) = @methods.fetch(name)

    # **What a method does with a block, if it takes one.** The declaration form carries
    # one kind — `:realtime_handler`, whose block becomes an independent function running
    # in the realtime context — because one kind is what exists. A second arrives with the
    # second method that needs it, and not before: a shape drawn from one example is a
    # shape drawn again at the second.
    def block_of(name) = @methods.dig(name, :block)

    def instance_type(typed_ast) = typed_ast.create_instance_type(@name, @struct)

    # What this side still carries. Everything here could leave the same way I2C did; the
    # ones that have not are the ones nothing has asked to move yet.
    CATALOG = CLASSES.merge(EXTRA, ONBOARD).freeze

    ALL = {}

    # A peripheral arrives by saying what it is, from wherever it happens to live. The
    # compiler holds no list of them — what a program may say to hardware is settled by
    # what is installed, and this is the only door.
    def self.register(name, entry) = ALL[name] = new(name, entry)

    CATALOG.each { |name, entry| register(name, entry) }

    def self.[](name) = ALL.fetch(name)

    def self.known?(name) = ALL.key?(name)

    def self.all = ALL.values

    def self.declarations = all.filter_map(&:declaration)

    def self.required_names = all.filter_map(&:required_name)

    def self.units_reached(low_ir) = all.flat_map { |one| one.units_reached(low_ir) }.uniq

    # Where a standard class declares itself. Nothing here says which ones exist — they
    # are found by looking rather than by naming, in every gem installed at the desk. The
    # ones this side still carries are above; the ones that have left are indistinguishable
    # from them once loaded.
    INSTALLED = "bareruby_prot/stdlib/*.rb"

    def self.load_installed = Gem.find_files(INSTALLED).sort.each { |one| require one }
  end
end

BareRubyProt::Peripheral.load_installed
