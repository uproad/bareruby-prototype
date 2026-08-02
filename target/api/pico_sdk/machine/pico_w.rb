# frozen_string_literal: true

module BareRubyProt
  module PicoSdkBinding
    # Raspberry Pi Pico W. Its indicator hangs off the radio rather than a pin, and GP25 —
    # where the plain board's LED sits — is the radio's select line on this one. Bringing
    # the chip up is a driver and a firmware blob, so this board asks for them.
    module PicoW
      def self.onboard_led_file = ONBOARD_LED_RADIO_FILE

      def self.onboard_led_libraries = [RADIO_LIBRARY]
    end

    MACHINES[:pico_w] = PicoW
  end
end
