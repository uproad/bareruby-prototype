# frozen_string_literal: true

module BareRubyProt
  module ArduinoBinding
    # FREENOVE ESP32-S3-WROOM, reached through the Arduino core for ESP32 rather than
    # through ESP-IDF. **It is the same board another binding already reaches**, and it is
    # here to show that which SDK answers for a board is a separate question from which
    # board it is: the machine is one, the two compositions are two, and a program says
    # nothing about either.
    module Esp32S3Wroom
      # What this core calls the board, and the one option of the dozen it offers that has
      # to be said. The generic ESP32-S3 entry is what a module like this one is built as —
      # a board with an entry of its own would be named here instead — and everything the
      # core defaults to is right for it except the flash: this is the N16R8 part, and a
      # board told it has four megabytes is a board with twelve nobody can reach.
      #
      # `USBMode=hwcdc` and `CDCOnBoot=default` are the defaults and are what this binding
      # wants: the chip's own USB comes up as a serial port that can always be written, and
      # `Serial` stays UART0 — which is where `printf` already goes, and which this board
      # brings out through its CH343 bridge.
      def self.fqbn = "esp32:esp32:esp32s3:FlashSize=16M"

      # The indicator is one WS2812 rather than a pin, so it is the RGB unit that answers
      # for this board.
      def self.onboard_led_file = ONBOARD_LED_RGB_FILE

      # A board that takes four images at four offsets, merged by the toolchain into the
      # one this name stands for.
      def self.artifact = "bareruby_program.bin"

      # **This core is built with `-fexceptions`**, so `--no-exceptions` decides something
      # here that it cannot decide on an AVR: the same binding reaches one board where
      # `begin` has an unwinder to land in and one where it never can.
      def self.exceptions? = true

      # **Which pin a peripheral came out on is this board's answer, and the unit that
      # drives it is the binding's.** So the numbers arrive as definitions the build hands
      # the compiler, and the units are written in terms of the names rather than the
      # numbers — the next board through this binding is a file like this one and nothing
      # else. They are the same numbers the other binding to this board records, because
      # they are facts about the board rather than about either SDK.
      #
      # The converter is twelve bits over the 3.1 V its widest attenuation reaches, which
      # is the core's default and is not calibrated.
      def self.definitions
        {
          "BARERUBY_ONBOARD_LED_PIN" => 48,
          "BARERUBY_ADC_MILLIVOLTS" => 3100, "BARERUBY_ADC_RESOLUTION" => 4095,
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
