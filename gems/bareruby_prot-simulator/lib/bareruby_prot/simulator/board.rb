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
    # The board the host build has none of, made of Ruby objects.
    #
    # **This is the binding, written on this side of the call.** Every function a binding
    # implements is trapped here, so what a program says to a pin reaches a `Gpio` rather
    # than a `fprintf`, and what it asks a pin reaches back out of one. The peripherals
    # are what a display shows and what a check reads; this class is how a call gets to
    # them, and what it does to the struct the program is carrying while it is at it.
    #
    # **The struct still has to be right.** Some of what a peripheral class does is
    # written as C that ships with it and runs here as instructions — reading a baud rate
    # back, folding a `setmode` into what is already set, working a duty cycle out of a
    # pulse width. Those read fields this side never sees written, so every trap that
    # changes a setting writes it where that C will look.
    class Board
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
        @onboard_led = OnboardLed.new
        @held = {}
        @pointers = {}
        @watching = nil
      end

      # ---- what is on the board -------------------------------------------------

      def gpio(pin = nil) = pin ? @gpio[pin] : @gpio

      def uart(unit = nil) = unit ? @uart[unit] : @uart

      def pwm(pin = nil) = pin ? @pwm[pin] : @pwm

      def adc(pin = nil) = pin ? @adc[pin] : @adc

      def i2c(unit = nil) = unit ? @i2c[unit] : @i2c

      def onboard_led = @onboard_led

      # Moving a pin from outside, which is the only way an input ever changes: nothing
      # is attached to this board but whoever is holding it. A fall a handler was
      # registered for is delivered before this returns, exactly as an interrupt would
      # reach a program between two instructions.
      def change(pin, level)
        pin = @gpio.fetch(pin)
        falling = pin.edge?(level)
        pin.level = level
        @machine.drive(pin.handler) if falling
      end

      def attach(machine) = @machine = machine

      # **A wait is where anything outside the program gets its turn.** Whatever is given
      # here runs every time the program waits, which is where an interrupt would reach a
      # board too — so a caller can move a pin, answer an ADC or put bytes on a wire while
      # the program is running rather than only before it starts or after it has stopped.
      def while_waiting(&watching) = @watching = watching

      # ---- what the program calls -----------------------------------------------

      def calls
        wait.merge(pins, waves, readings, ports, buses, indicator)
      end

      private

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

      def held(machine) = @held.fetch(machine.argument(0))

      def store(machine, pointer, values)
        values.each_with_index do |value, index|
          machine.memory.write32(pointer + (index * 4), value)
        end
      end

      # ---- waiting --------------------------------------------------------------

      def started(_machine) = nil

      def ticks(machine) = machine.answer(@clock.ticks_ms)

      def delayed(machine) = @clock.advance(machine.signed_argument(0))

      def slept(machine)
        waited(machine, machine.signed_argument(0) * Clock::SECOND)
        machine.answer(machine.argument(0))
      end

      def slept_ms(machine)
        waited(machine, machine.signed_argument(0) * Clock::MILLISECOND)
        machine.answer(machine.argument(0))
      end

      def asleep(machine) = waited(machine, machine.signed_argument(0) * Clock::SECOND)

      def asleep_ms(machine)
        waited(machine, machine.signed_argument(0) * Clock::MILLISECOND)
      end

      def asleep_us(machine) = waited(machine, machine.signed_argument(0))

      # A wait is where a handler gets to run, because a handler runs in thread mode
      # rather than in the interrupt, and it is where the run finds out it is over.
      def waited(machine, microseconds)
        @clock.advance(microseconds)
        @watching&.call(self)
        deliver(machine) unless machine.argument(1).zero?
        machine.stop if @clock.over?
      end

      def deliver(machine)
        @uart.each_value do |port|
          next unless port.handler && port.pending.positive?

          machine.drive(port.handler, @pointers.fetch(port), port.events)
        end
      end

      # ---- pins -----------------------------------------------------------------

      def pin_opened(machine)
        pin = machine.signed_argument(1)
        params = machine.signed_argument(2)
        @gpio[pin] = hold(machine.argument(0), Gpio.new(pin, params))
        store(machine, machine.argument(0), [pin, params])
      end

      def pin_written(machine)
        held(machine).level = machine.signed_argument(1)
        machine.answer(TAKEN)
      end

      def pin_read(machine) = machine.answer(held(machine).level)

      def pin_high(machine) = machine.answer(held(machine).high? ? 1 : 0)

      def pin_low(machine) = machine.answer(held(machine).low? ? 1 : 0)

      def pin_watched(machine)
        held(machine).watch(machine.signed_argument(1), machine.argument(2))
      end

      # ---- square waves ---------------------------------------------------------

      def wave_opened(machine)
        pin = machine.signed_argument(1)
        wave = hold(machine.argument(0), Pwm.new(pin, machine.signed_argument(2),
                                                 machine.signed_argument(3)))
        @pwm[pin] = wave
        store(machine, machine.argument(0), [wave.pin, wave.slice, wave.frequency])
      end

      def wave_frequency(machine) = held(machine).frequency = machine.signed_argument(1)

      def wave_period(machine) = held(machine).period_us = machine.signed_argument(1)

      def wave_duty(machine) = held(machine).duty = machine.signed_argument(1)

      def wave_pulse_width(machine)
        held(machine).pulse_width_us = machine.signed_argument(1)
      end

      # ---- readings -------------------------------------------------------------

      def reading_opened(machine)
        pin = machine.signed_argument(1)
        @adc[pin] = hold(machine.argument(0), Adc.new(pin))
        store(machine, machine.argument(0), [pin, @adc[pin].channel])
      end

      def reading_taken(machine) = machine.answer(held(machine).read)

      # ---- serial ports ---------------------------------------------------------

      def port_opened(machine)
        pointer = machine.argument(0)
        settings = (1..10).map { |index| machine.signed_argument(index) }
        port = hold(pointer, Uart.new(settings.first, settings.drop(1)))
        port.wire = @wire
        @uart[port.unit] = port
        store(machine, pointer, settings)
        machine.memory.write64(pointer + LINE_ENDING, machine.place("\n"))
      end

      def port_set(machine)
        port = held(machine)
        port.settle((1..7).map { |index| machine.signed_argument(index) })
        store(machine, machine.argument(0) + 12, port.frame)
      end

      def port_written(machine)
        text = machine.string(machine.argument(1))
        held(machine).transmit(text)
        machine.answer(text.bytesize)
      end

      def port_put(machine)
        line = machine.string(machine.argument(1))
        port(machine).then { |found| found.transmit("#{line}#{found.line_ending}") }
      end

      def port_printed(machine)
        port(machine).transmit(printed(machine))
      end

      def port_printed_line(machine)
        port(machine).then { |found| found.transmit("#{printed(machine)}#{found.line_ending}") }
      end

      def printed(machine)
        rendered(machine, machine.argument(1), Passed.new(machine, 2))
      end

      # What a line ends with is the program's to change, and it changes it in the struct
      # without telling anybody, so it is read back from there every time it is needed.
      def port(machine)
        found = held(machine)
        found.line_ending =
          machine.string(machine.memory.read64(machine.argument(0) + LINE_ENDING))
        found
      end

      def port_taken(machine) = machine.answer(held(machine).take || NOTHING)

      def port_peeked(machine) = machine.answer(held(machine).peek || NOTHING)

      def port_pending(machine) = machine.answer(held(machine).pending)

      def port_owed(machine) = machine.answer(0)

      def port_broken(machine) = held(machine).break_for(machine.signed_argument(1))

      def port_flushed(_machine) = nil

      def port_received_cleared(machine) = held(machine).clear_received

      def port_sent_cleared(machine) = held(machine).clear_transmitted

      def port_watched(machine)
        held(machine).watch(machine.signed_argument(1), machine.argument(2))
      end

      # ---- buses ----------------------------------------------------------------

      def bus_opened(machine)
        unit = machine.signed_argument(1)
        frequency = machine.signed_argument(2)
        @i2c[unit] = hold(machine.argument(0), I2c.new(unit, frequency))
        @i2c[unit].wire = @wire
        store(machine, machine.argument(0), [unit, frequency])
      end

      def bus_written(machine)
        length = machine.signed_argument(3)
        held(machine).write(machine.signed_argument(1), machine.bytes(machine.argument(2), length))
        machine.answer(length)
      end

      # The one call that answers with something the runtime has to build: a string in
      # the arena the program handed over, filled a byte at a time by the same functions
      # the program's own code would have called.
      def bus_read(machine)
        outputs = machine.bytes(machine.argument(4), machine.signed_argument(5))
        answered = held(machine).read(machine.signed_argument(2), machine.signed_argument(3),
                                      outputs)
        machine.answer(strung(machine, machine.argument(1), answered))
      end

      def strung(machine, arena, bytes)
        string = machine.drive(machine.address_of("bareruby_string_new"), arena,
                               machine.place(""))
        append = machine.address_of("bareruby_string_append_byte")
        bytes.each_byte { |byte| machine.drive(append, string, byte) }
        string
      end

      # ---- the indicator --------------------------------------------------------

      def indicator_opened(machine)
        hold(machine.argument(0), @onboard_led)
        store(machine, machine.argument(0), [@onboard_led.level])
      end

      def indicator_written(machine)
        @onboard_led.level = machine.signed_argument(1)
        store(machine, machine.argument(0), [@onboard_led.level])
      end
    end
  end
end
