# frozen_string_literal: true

module BareRubyProt
  module ArduinoBinding
    module UIAPduinoCH32V003
      def self.fqbn = "UIAP:ch32v:CH32V00x_EVT:pnum=CH32V003V1DOT4"
      def self.onboard_led_file = ONBOARD_LED_PIN_FILE
      def self.onboard_led_libraries = []
      def self.artifact = "bareruby_program.bin"
      def self.exceptions? = false
      def self.definitions = { "LED_BUILTIN" => 2 }
    end

    MACHINES[:uiapduino_ch32v003] = UIAPduinoCH32V003
  end
end
