# frozen_string_literal: true

module BareRubyProt
  module HostBinding
    # The machine doing the compiling has no indicator to reach, so the call is traced
    # instead of driving anything.
    module None
      def self.onboard_led_file = ONBOARD_LED_NONE_FILE

      def self.onboard_led_libraries = []
    end

    MACHINES[:none] = None
  end
end
