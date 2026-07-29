# frozen_string_literal: true

module BareRubyProt
  # One piece of hardware the language offers as a class: what it is called, the struct
  # the binding keeps its state in, the constants it publishes, and the binding functions
  # behind its constructor and its methods. Which implementation those functions have is
  # the second stage's business; what a program may say to them is settled here.
  class Peripheral
    # One-hot, matching PicoRuby, so that directions and pulls combine with | the way
    # the standard guideline spells them.
    CLASSES = {
      GPIO: {
        struct: :bareruby_gpio_t,
        constants: { IN: 1, OUT: 2, HIGH_Z: 4, PULL_UP: 8, PULL_DOWN: 16, OPEN_DRAIN: 32, EDGE_FALL: 4 },
        constructor: { function: :bareruby_gpio_init, parameter_types: %i[Int32 Int32] },
        methods: {
          write: { function: :bareruby_gpio_write, parameter_types: %i[Int32], return_type: :Nil },
          read: { function: :bareruby_gpio_read, parameter_types: [], return_type: :Int32 },
          high?: { function: :bareruby_gpio_high, parameter_types: [], return_type: :Bool },
          low?: { function: :bareruby_gpio_low, parameter_types: [], return_type: :Bool }
        }
      }
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
      PWM: {
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
      },
      I2C: {
        struct: :bareruby_i2c_t,
        constants: {},
        constructor: {
          function: :bareruby_i2c_init,
          parameter_types: %i[Int32],
          keywords: { frequency: 100_000 }
        },
        methods: {
          write: { function: :bareruby_i2c_write, parameter_types: [], return_type: :Int32 },
          read: { function: :bareruby_i2c_read, parameter_types: [], return_type: :arena_string }
        }
      }
    }.freeze

    # sleep waits from the moment it is called, so a loop drifts by however long its
    # body takes. asleep waits from the moment the previous asleep returned, which is
    # what a loop that has to keep a period needs.

    attr_reader :name, :struct

    def initialize(name, entry)
      @name = name
      @struct = entry[:struct]
      @constants = entry[:constants]
      @constructor = entry[:constructor]
      @methods = entry[:methods]
    end

    def constant(name) = @constants.fetch(name)

    def constructor_function = @constructor[:function]

    def constructor_keywords = @constructor[:keywords] || {}

    def method_signature(name) = @methods.fetch(name)

    def instance_type(typed_ast) = typed_ast.create_instance_type(@name, @struct)

    CATALOG = CLASSES.merge(EXTRA, ONBOARD).freeze
    ALL = CATALOG.to_h { |name, entry| [name, new(name, entry)] }.freeze

    def self.[](name) = ALL.fetch(name)

    def self.known?(name) = ALL.key?(name)
  end
end
