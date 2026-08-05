# frozen_string_literal: true

require_relative "binding"
require_relative "build"
require_relative "toolchain"
require_relative "flash"

# What this binding brings: the machines it reaches, and the compositions it can produce
# for them. Everything the compiler knows about them arrives from here.
#
# The first instruction set here whose natural word is not 32 bits: an int is 16 bits and
# a pointer is 16 bits, while an int32_t is a long. The triple names no chip, because it
# does not settle one — an ATmega328P and an ATmega2560 are both this, and which of them a
# build is for is said with -mmcu= further down.
module BareRubyProt
  module ArduinoBinding
    AVR = Isa.new("avr-none")
  end

  Target.register(
    "arduino-mega2560", short: "mega",
    isa: ArduinoBinding::AVR, substrate: Substrate::BARE_METAL,
    binding: ArduinoBinding, machine: Machine.register(:mega2560, chip: "atmega2560")
  )
end
