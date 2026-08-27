# frozen_string_literal: true

module BareRubyProt
  module EspIdfBinding
    # FREENOVE ESP32-S3-WROOM. An ESP32-S3-WROOM-1 N16R8 module — Xtensa LX7, two cores at
    # 240 MHz, 16 MB of flash and 8 MB of PSRAM — on a board that brings its serial port
    # out twice, through a CH343 bridge and through the chip's own USB, and its indicator
    # out as a single addressable RGB device rather than as a pin.
    module Esp32S3Wroom
      # What ESP-IDF calls the chip. It is the SDK's word rather than the board's: the
      # same board reached through another ecosystem would be spelled differently, and
      # this is what picks the compiler, the linker script and the register headers.
      def self.idf_target = "esp32s3"

      # How much flash the module carries, as the chip reports it. The image says so in
      # its own header, and a bootloader that finds a smaller answer there than the chip
      # has is a board with flash nobody can reach.
      def self.flash_size = "16MB"

      # The indicator is one WS2812 rather than a pin, so it is the RGB unit that answers
      # for this board.
      def self.onboard_led_file = ONBOARD_LED_RGB_FILE

      # **Which pin a peripheral came out on is this board's answer, and the unit that
      # drives it is the binding's.** So the numbers arrive as definitions the build hands
      # the compiler, and the units are written in terms of the names rather than the
      # numbers — the next board through this binding is a file like this one and nothing
      # else. Nothing is looked up at runtime: a pin is a constant of the board.
      def self.definitions
        {
          "BARERUBY_ONBOARD_LED_PIN" => 48,
          "BARERUBY_I2C0_SDA_PIN" => 8, "BARERUBY_I2C0_SCL_PIN" => 9,
          "BARERUBY_I2C1_SDA_PIN" => 10, "BARERUBY_I2C1_SCL_PIN" => 11,
          "BARERUBY_UART0_TXD_PIN" => 43, "BARERUBY_UART0_RXD_PIN" => 44,
          "BARERUBY_UART1_TXD_PIN" => 17, "BARERUBY_UART1_RXD_PIN" => 18
        }
      end
    end

    MACHINES[:esp32_s3_wroom] = Esp32S3Wroom
  end
end
