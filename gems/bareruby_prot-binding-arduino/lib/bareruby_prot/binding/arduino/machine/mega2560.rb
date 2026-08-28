# frozen_string_literal: true

module BareRubyProt
  module ArduinoBinding
    # Arduino Mega 2560. Its indicator is on a pin, and the core's board header names
    # which.
    module Mega2560
      # What this core calls the board — packager, architecture, board, and the chip the
      # board's entry leaves open. It is the core's word rather than the board's: the
      # same three parts reach an ATmega1280 by changing only the last of them, and
      # another core reaching this board would want a different spelling entirely. So it
      # lives here, where the machine and the binding meet, and not on the machine.
      def self.fqbn = "arduino:avr:mega:cpu=atmega2560"

      def self.onboard_led_file = ONBOARD_LED_PIN_FILE

      def self.onboard_led_libraries = []

      # One image, and the core's own name for it.
      def self.artifact = "bareruby_program.hex"

      # **This core compiles with `-fno-exceptions` and this libc carries no unwinder**, so
      # there is nothing here for `--no-exceptions` to decide: `begin` has nowhere to land
      # either way round.
      def self.exceptions? = false

      # **Which pin a peripheral came out on is this board's answer, and the unit that
      # drives it is the binding's.** So the numbers arrive as definitions the build hands
      # the compiler, and the units are written in terms of the names rather than the
      # numbers. Nothing is looked up at runtime: a pin is a constant of the board.
      #
      # The transmit pins are here because a break is sent by taking one back from the
      # port and holding it low, which is the one thing this core offers no call for. The
      # converter is ten bits against a five-volt reference, which is a fact about the
      # board's wiring as much as about the chip.
      def self.definitions
        {
          "BARERUBY_ADC_MILLIVOLTS" => 5000, "BARERUBY_ADC_RESOLUTION" => 1023,
          "BARERUBY_UART0_TXD_PIN" => 1, "BARERUBY_UART1_TXD_PIN" => 18,
          "BARERUBY_UART2_TXD_PIN" => 16, "BARERUBY_UART3_TXD_PIN" => 14
        }
      end
    end

    MACHINES[:mega2560] = Mega2560
  end
end
