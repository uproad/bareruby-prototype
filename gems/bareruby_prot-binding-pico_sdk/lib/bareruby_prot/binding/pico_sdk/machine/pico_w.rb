# frozen_string_literal: true

module BareRubyProt
  module PicoSdkBinding
    # Raspberry Pi Pico W. Its indicator hangs off the radio rather than a pin, and GP25 —
    # where the plain board's LED sits — is the radio's select line on this one. Bringing
    # the chip up is a driver and a firmware blob, so this board asks for them.
    module PicoW
      # What pico-sdk calls this board. PICO_PLATFORM is the SDK's word rather than
      # the chip's: an RP2350 answers to rp2350-arm-s or rp2350-riscv once which of
      # its two cores to build for is chosen.
      def self.pico_board = "pico_w"

      def self.pico_platform = "rp2040"

      def self.usb_product = "BareRuby Debug Firm RP Pico1W"

      # How much flash this board carries. The reserved page holding what the board is
      # called sits at the top of it, so this is what says where.
      def self.flash_bytes = 2 * 1024 * 1024

      def self.onboard_led_file = ONBOARD_LED_RADIO_FILE

      def self.onboard_led_libraries = [RADIO_LIBRARY]
    end

    MACHINES[:pico_w] = PicoW
  end
end
