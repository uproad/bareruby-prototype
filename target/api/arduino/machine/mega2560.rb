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
      # lives here, where the board and the API meet, and not on the board.
      def self.fqbn = "arduino:avr:mega:cpu=atmega2560"

      def self.onboard_led_file = ONBOARD_LED_PIN_FILE

      def self.onboard_led_libraries = []
    end

    MACHINES[:mega2560] = Mega2560
  end
end
