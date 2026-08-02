# frozen_string_literal: true

module BareRubyProt
  module PicoSdkBinding
    # Raspberry Pi Pico 2 W. Wireless like a Pico W, on an RP2350.
    module Pico2W
      def self.onboard_led_file = ONBOARD_LED_RADIO_FILE

      def self.onboard_led_libraries = [RADIO_LIBRARY]
    end

    MACHINES[:pico2_w] = Pico2W
  end
end
