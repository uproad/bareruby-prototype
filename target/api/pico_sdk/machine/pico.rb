# frozen_string_literal: true

module BareRubyProt
  module PicoSdkBinding
    # Raspberry Pi Pico. Its indicator is on a pin, and the SDK's board header names which.
    module Pico
      def self.onboard_led_file = ONBOARD_LED_PIN_FILE

      def self.onboard_led_libraries = []
    end

    MACHINES[:pico] = Pico
  end
end
