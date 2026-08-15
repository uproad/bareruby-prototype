# frozen_string_literal: true

module BareRubyProt
  module PicoSdkBinding
    # Raspberry Pi Pico 2. The same board header answer as a Pico, on a different chip.
    module Pico2
      # What pico-sdk calls this board. PICO_PLATFORM is the SDK's word rather than
      # the chip's: an RP2350 answers to rp2350-arm-s or rp2350-riscv once which of
      # its two cores to build for is chosen.
      def self.pico_board = "pico2"

      def self.pico_platform = "rp2350"

      def self.usb_product = "BareRuby Debug Firm RP Pico2"

      # How much flash this board carries. The reserved page holding what the board is
      # called sits at the top of it, so this is what says where.
      def self.flash_bytes = 4 * 1024 * 1024

      def self.onboard_led_file = ONBOARD_LED_PIN_FILE

      def self.onboard_led_libraries = []
    end

    MACHINES[:pico2] = Pico2
  end
end
