# frozen_string_literal: true

module BareRubyProt
  module HostBinding
    # The machine doing the compiling. Its indicator is not on a header and has no pin
    # number, which is exactly what an on-board LED is on every other machine too — where
    # it is belongs to the board. Here it is one of the things the simulator holds; a run
    # that is executed rather than interpreted traces the call instead.
    module Host
      def self.onboard_led_file = ONBOARD_LED_FILE

      def self.onboard_led_libraries = []
    end

    MACHINES[:host] = Host
  end
end
