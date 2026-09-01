# frozen_string_literal: true

require_relative "binding"
require_relative "build"
require_relative "toolchain"
require_relative "flash"

# What this binding brings: the machines it reaches, and the compositions it can produce
# for them. Everything the compiler knows about them arrives from here.
#
# **The instruction set is named per board rather than per binding**, because the Arduino
# core is one surface to call spread over boards that share none: an eight-bit AVR whose
# int is 16 bits and whose pointer is 16 bits, and an Xtensa LX7 that is 32 bits
# throughout. The AVR triple names no chip, because it does not settle one — an ATmega328P
# and an ATmega2560 are both this, and which of them a build is for is said with `-mmcu=`
# further down, out of the FQBN.
#
# **One of these machines is reached by a second binding too**, so the name here carries
# the core as well as the board. A composition is what is being named, and this board's
# name alone no longer says which composition.
module BareRubyProt
  module ArduinoBinding
    AVR = Isa.new("avr-none")
    XTENSA_LX7_S3 = Isa.new("xtensa-esp32s3-elf")
  end

  Target.register(
    "arduino-mega2560",
    isa: ArduinoBinding::AVR, substrate: Substrate::BARE_METAL,
    binding: ArduinoBinding, machine: Machine.register(:mega2560, chip: "atmega2560")
  )

  Target.register(
    "freenove-esp32-s3-wroom-arduino",
    isa: ArduinoBinding::XTENSA_LX7_S3, substrate: Substrate::BARE_METAL,
    binding: ArduinoBinding, machine: Machine.register(:esp32_s3_wroom, chip: "esp32s3")
  )
end
