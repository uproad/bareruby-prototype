# frozen_string_literal: true

module BareRubyProt
  module PicoSdkBinding
    # Raspberry Pi Pico. Its indicator is on a pin, and the SDK's board header names which.
    module Pico
      # What pico-sdk calls this board. PICO_PLATFORM is the SDK's word rather than
      # the chip's: an RP2350 answers to rp2350-arm-s or rp2350-riscv once which of
      # its two cores to build for is chosen.
      def self.pico_board = "pico"

      def self.pico_platform = "rp2040"

      def self.usb_product = "BareRuby Debug Firm RP Pico1"

      # How much flash this board carries. The reserved page holding what the board is
      # called sits at the top of it, so this is what says where.
      def self.flash_bytes = 2 * 1024 * 1024

      def self.onboard_led_file = ONBOARD_LED_PIN_FILE

      def self.onboard_led_libraries = []
    end

    MACHINES[:pico] = Pico
  end
end
