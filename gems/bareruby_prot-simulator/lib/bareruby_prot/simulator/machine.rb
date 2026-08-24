# frozen_string_literal: true

require_relative "formatting"
require_relative "adc"
require_relative "clock"
require_relative "gpio"
require_relative "i2c"
require_relative "onboard_led"
require_relative "pwm"
require_relative "uart"

module BareRubyProt
  module Simulator
    # **The machine doing the compiling, with what it carries.** A hosted build has a
    # machine like any other — this desk — and these are its peripherals: pins that hold a
    # level, ports that keep what they sent, a clock that moves. Nothing here is modelled
    # after a board; it is what a call arrives at when the binding (`Binding`) hands one
    # over.
    #
    # The peripherals are what a display shows and what a check reads; this class is how a
    # call reaches them, and what it does to the struct the program is carrying while it
    # is at it.
    #
    # **The struct still has to be right.** Some of what a peripheral class does is
    # written as C that ships with it and runs as instructions — reading a baud rate back,
    # folding a `setmode` into what is already set, working a duty cycle out of a pulse
    # width. Those read fields this side never sees written, so every trap that changes a
    # setting writes it where that C will look.
    class Machine
      include Formatting

      # Where a serial port keeps what its lines end with: after ten `int32_t` fields,
      # on the first eight-byte boundary after them.
      LINE_ENDING = 40

      # What `write` answers, which is not a reading of the pin but whether the write
      # was taken.
      TAKEN = 0

      # What a receive call answers when the queue is empty: -1, in the width it is read
      # back at.
      NOTHING = 0xFFFF_FFFF

      attr_reader :clock

      def initialize(clock:, wire: nil)
        @clock = clock
        @wire = wire
        @gpio = {}
        @uart = {}
        @pwm = {}
        @adc = {}
        @i2c = {}
        @onboard_led = nil
        @held = {}
        @pointers = {}
        @watching = nil
        @binding = nil
      end

      # ---- what is on the board -------------------------------------------------

      def gpio(pin = nil) = pin ? @gpio[pin] : @gpio

      def uart(unit = nil) = unit ? @uart[unit] : @uart

      def pwm(pin = nil) = pin ? @pwm[pin] : @pwm

      def adc(pin = nil) = pin ? @adc[pin] : @adc

      def i2c(unit = nil) = unit ? @i2c[unit] : @i2c

      # The indicator, once the program has opened one. Like every other peripheral here,
      # it does not exist until it has been asked for — a machine has one, but a program
      # that never lights it has not met it.
      def onboard_led = @onboard_led

      # Moving a pin from outside, which is the only way an input ever changes: nothing
      # is attached to this board but whoever is holding it. A fall a handler was
      # registered for is delivered before this returns, exactly as an interrupt would
      # reach a program between two instructions.
      def change(pin, level)
        pin = @gpio.fetch(pin)
        falling = pin.edge?(level)
        pin.level = level
        @binding.drive(pin.handler) if falling
      end

      def attach(binding) = @binding = binding

      # **A wait is where anything outside the program gets its turn.** Whatever is given
      # here runs every time the program waits, which is where an interrupt would reach a
      # board too — so a caller can move a pin, answer an ADC or put bytes on a wire while
      # the program is running rather than only before it starts or after it has stopped.
      def while_waiting(&watching) = @watching = watching

      # **The whole machine, as plain data.** The readers above answer objects, which is
      # what Ruby wants; this answers the same readings in a shape that can be handed to
      # something that is not Ruby — a display in another process, a file, a check written
      # elsewhere. Nothing here knows about JSON: turning this into bytes belongs to
      # whoever is doing the handing.
      def snapshot
        { ms: @clock.ticks_ms,
          gpio: keyed(@gpio), uart: keyed(@uart), pwm: keyed(@pwm),
          adc: keyed(@adc), i2c: keyed(@i2c), onboard_led: @onboard_led&.snapshot }
      end

      # ---- what the program calls -----------------------------------------------

      def calls
        wait.merge(pins, waves, readings, ports, buses, indicator)
      end

      private

      # A table of peripherals, each answering for itself. The keys stay what the program
      # opened them as.
      def keyed(peripherals) = peripherals.transform_values(&:snapshot)

      def wait
        {
          "bareruby_startup" => method(:started),
          "bareruby_ticks_ms" => method(:ticks),
          "bareruby_machine_delay_us" => method(:delayed),
          "bareruby_sleep" => method(:slept),
          "bareruby_sleep_ms" => method(:slept_ms),
          "bareruby_asleep" => method(:asleep),
          "bareruby_asleep_ms" => method(:asleep_ms),
          "bareruby_asleep_us" => method(:asleep_us)
        }
      end

      def pins
        {
          "bareruby_gpio_init" => method(:pin_opened),
          "bareruby_gpio_write" => method(:pin_written),
          "bareruby_gpio_read" => method(:pin_read),
          "bareruby_gpio_high" => method(:pin_high),
          "bareruby_gpio_low" => method(:pin_low),
          "bareruby_gpio_irq" => method(:pin_watched)
        }
      end

      def waves
        {
          "bareruby_pwm_init" => method(:wave_opened),
          "bareruby_pwm_apply_frequency" => method(:wave_frequency),
          "bareruby_pwm_apply_period_us" => method(:wave_period),
          "bareruby_pwm_apply_duty" => method(:wave_duty),
          "bareruby_pwm_apply_pulse_width_us" => method(:wave_pulse_width)
        }
      end

      def readings
        {
          "bareruby_adc_init" => method(:reading_opened),
          "bareruby_adc_read" => method(:reading_taken),
          "bareruby_adc_read_raw" => method(:reading_taken)
        }
      end

      def ports
        {
          "bareruby_uart_init" => method(:port_opened),
          "bareruby_uart_setmode" => method(:port_set),
          "bareruby_uart_write" => method(:port_written),
          "bareruby_uart_puts" => method(:port_put),
          "bareruby_uart_printf" => method(:port_printed),
          "bareruby_uart_printf_line" => method(:port_printed_line),
          "bareruby_uart_getbyte" => method(:port_taken),
          "bareruby_uart_peek" => method(:port_peeked),
          "bareruby_uart_bytes_available" => method(:port_pending),
          "bareruby_uart_bytes_to_write" => method(:port_owed),
          "bareruby_uart_break" => method(:port_broken),
          "bareruby_uart_flush" => method(:port_flushed),
          "bareruby_uart_clear_rx_buffer" => method(:port_received_cleared),
          "bareruby_uart_clear_tx_buffer" => method(:port_sent_cleared),
          "bareruby_uart_irq" => method(:port_watched)
        }
      end

      def buses
        {
          "bareruby_i2c_init" => method(:bus_opened),
          "bareruby_i2c_write" => method(:bus_written),
          "bareruby_i2c_read" => method(:bus_read)
        }
      end

      def indicator
        {
          "bareruby_onboard_led_init" => method(:indicator_opened),
          "bareruby_onboard_led_write" => method(:indicator_written)
        }
      end

      # ---- holding a peripheral -------------------------------------------------

      # The struct a program is carrying is what says which peripheral a later call is
      # about, so its address is what one is filed under.
      def hold(pointer, peripheral)
        @held[pointer] = peripheral
        @pointers[peripheral] = pointer
        peripheral
      end

      def held(binding) = @held.fetch(binding.argument(0))

      def store(binding, pointer, values)
        values.each_with_index do |value, index|
          binding.memory.write32(pointer + (index * 4), value)
        end
      end

      # ---- waiting --------------------------------------------------------------

      def started(_binding) = nil

      def ticks(binding) = binding.answer(@clock.ticks_ms)

      def delayed(binding) = @clock.advance(binding.signed_argument(0))

      def slept(binding)
        waited(binding, binding.signed_argument(0) * Clock::SECOND)
        binding.answer(binding.argument(0))
      end

      def slept_ms(binding)
        waited(binding, binding.signed_argument(0) * Clock::MILLISECOND)
        binding.answer(binding.argument(0))
      end

      def asleep(binding) = waited(binding, binding.signed_argument(0) * Clock::SECOND)

      def asleep_ms(binding)
        waited(binding, binding.signed_argument(0) * Clock::MILLISECOND)
      end

      def asleep_us(binding) = waited(binding, binding.signed_argument(0))

      # A wait is where a handler gets to run, because a handler runs in thread mode
      # rather than in the interrupt, and it is where the run finds out it is over.
      def waited(binding, microseconds)
        @clock.advance(microseconds)
        @watching&.call(self)
        deliver(binding) unless binding.argument(1).zero?
        binding.stop if @clock.over?
      end

      def deliver(binding)
        @uart.each_value do |port|
          next unless port.handler && port.pending.positive?

          binding.drive(port.handler, @pointers.fetch(port), port.events)
        end
      end

      # ---- pins -----------------------------------------------------------------

      def pin_opened(binding)
        pin = binding.signed_argument(1)
        params = binding.signed_argument(2)
        @gpio[pin] = hold(binding.argument(0), Gpio.new(pin, params))
        store(binding, binding.argument(0), [pin, params])
      end

      def pin_written(binding)
        held(binding).level = binding.signed_argument(1)
        binding.answer(TAKEN)
      end

      def pin_read(binding) = binding.answer(held(binding).level)

      def pin_high(binding) = binding.answer(held(binding).high? ? 1 : 0)

      def pin_low(binding) = binding.answer(held(binding).low? ? 1 : 0)

      def pin_watched(binding)
        held(binding).watch(binding.signed_argument(1), binding.argument(2))
      end

      # ---- square waves ---------------------------------------------------------

      def wave_opened(binding)
        pin = binding.signed_argument(1)
        wave = hold(binding.argument(0), Pwm.new(pin, binding.signed_argument(2),
                                                 binding.signed_argument(3)))
        @pwm[pin] = wave
        store(binding, binding.argument(0), [wave.pin, wave.slice, wave.frequency])
      end

      def wave_frequency(binding) = held(binding).frequency = binding.signed_argument(1)

      def wave_period(binding) = held(binding).period_us = binding.signed_argument(1)

      def wave_duty(binding) = held(binding).duty = binding.signed_argument(1)

      def wave_pulse_width(binding)
        held(binding).pulse_width_us = binding.signed_argument(1)
      end

      # ---- readings -------------------------------------------------------------

      def reading_opened(binding)
        pin = binding.signed_argument(1)
        @adc[pin] = hold(binding.argument(0), Adc.new(pin))
        store(binding, binding.argument(0), [pin, @adc[pin].channel])
      end

      def reading_taken(binding) = binding.answer(held(binding).read)

      # ---- serial ports ---------------------------------------------------------

      def port_opened(binding)
        pointer = binding.argument(0)
        settings = (1..10).map { |index| binding.signed_argument(index) }
        port = hold(pointer, Uart.new(settings.first, settings.drop(1)))
        port.wire = @wire
        @uart[port.unit] = port
        store(binding, pointer, settings)
        binding.memory.write64(pointer + LINE_ENDING, binding.place("\n"))
      end

      def port_set(binding)
        port = held(binding)
        port.settle((1..7).map { |index| binding.signed_argument(index) })
        store(binding, binding.argument(0) + 12, port.frame)
      end

      def port_written(binding)
        text = binding.string(binding.argument(1))
        held(binding).transmit(text)
        binding.answer(text.bytesize)
      end

      def port_put(binding)
        line = binding.string(binding.argument(1))
        port(binding).then { |found| found.transmit("#{line}#{found.line_ending}") }
      end

      def port_printed(binding)
        port(binding).transmit(printed(binding))
      end

      def port_printed_line(binding)
        port(binding).then { |found| found.transmit("#{printed(binding)}#{found.line_ending}") }
      end

      def printed(binding)
        rendered(binding, binding.argument(1), Passed.new(binding, 2))
      end

      # What a line ends with is the program's to change, and it changes it in the struct
      # without telling anybody, so it is read back from there every time it is needed.
      def port(binding)
        found = held(binding)
        found.line_ending =
          binding.string(binding.memory.read64(binding.argument(0) + LINE_ENDING))
        found
      end

      def port_taken(binding) = binding.answer(held(binding).take || NOTHING)

      def port_peeked(binding) = binding.answer(held(binding).peek || NOTHING)

      def port_pending(binding) = binding.answer(held(binding).pending)

      def port_owed(binding) = binding.answer(0)

      def port_broken(binding) = held(binding).break_for(binding.signed_argument(1))

      def port_flushed(_binding) = nil

      def port_received_cleared(binding) = held(binding).clear_received

      def port_sent_cleared(binding) = held(binding).clear_transmitted

      def port_watched(binding)
        held(binding).watch(binding.signed_argument(1), binding.argument(2))
      end

      # ---- buses ----------------------------------------------------------------

      def bus_opened(binding)
        unit = binding.signed_argument(1)
        frequency = binding.signed_argument(2)
        @i2c[unit] = hold(binding.argument(0), I2c.new(unit, frequency))
        @i2c[unit].wire = @wire
        store(binding, binding.argument(0), [unit, frequency])
      end

      def bus_written(binding)
        length = binding.signed_argument(3)
        held(binding).write(binding.signed_argument(1), binding.bytes(binding.argument(2), length))
        binding.answer(length)
      end

      # The one call that answers with something the runtime has to build: a string in
      # the arena the program handed over, filled a byte at a time by the same functions
      # the program's own code would have called.
      def bus_read(binding)
        outputs = binding.bytes(binding.argument(4), binding.signed_argument(5))
        answered = held(binding).read(binding.signed_argument(2), binding.signed_argument(3),
                                      outputs)
        binding.answer(strung(binding, binding.argument(1), answered))
      end

      def strung(binding, arena, bytes)
        string = binding.drive(binding.address_of("bareruby_string_new"), arena,
                               binding.place(""))
        append = binding.address_of("bareruby_string_append_byte")
        bytes.each_byte { |byte| binding.drive(append, string, byte) }
        string
      end

      # ---- the indicator --------------------------------------------------------

      def indicator_opened(binding)
        @onboard_led = hold(binding.argument(0), OnboardLed.new)
        store(binding, binding.argument(0), [@onboard_led.level])
      end

      def indicator_written(binding)
        indicator = held(binding)
        indicator.level = binding.signed_argument(1)
        store(binding, binding.argument(0), [indicator.level])
      end
    end
  end
end
