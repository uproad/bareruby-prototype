# frozen_string_literal: true

module BareRubyProt
  module PicoSdkBinding
    # Raspberry Pi Pico 2. The same board header answer as a Pico, on a different chip.
    module Pico2
      def self.onboard_led_file = ONBOARD_LED_PIN_FILE

      def self.onboard_led_libraries = []
    end

    MACHINES[:pico2] = Pico2
  end
end
