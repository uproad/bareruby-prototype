# frozen_string_literal: true

module BareRubyProt
  module Stm32CubeBinding
    # ST NUCLEO-F446RE. LD2 is on a pin, and the CubeMX project names which — the same way
    # a Pico reaches its own, said in HAL.
    module NucleoF446re
      def self.onboard_led_file = ONBOARD_LED_PIN_FILE

      def self.onboard_led_libraries = []
    end

    MACHINES[:nucleo_f446re] = NucleoF446re
  end
end
