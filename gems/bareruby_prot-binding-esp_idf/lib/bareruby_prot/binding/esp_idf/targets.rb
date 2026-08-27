# frozen_string_literal: true

require_relative "binding"
require_relative "build"
require_relative "toolchain"
require_relative "flash"

# What this binding brings: the machines it reaches, and the compositions it can produce
# for them. Everything the compiler knows about them arrives from here.
#
# **The instruction set is named per board rather than per binding**, because this family
# is split across two of them — Xtensa on the ESP32, S2 and S3, RISC-V on the C3, C6 and
# H2 — and one ESP-IDF reaches all of them. The triple says which Xtensa, too: the LX6 in
# an ESP32 and the LX7 in this one are configured differently enough that a compiler built
# for one does not serve the other.
module BareRubyProt
  module EspIdfBinding
    XTENSA_LX7_S3 = Isa.new("xtensa-esp32s3-elf")
  end

  Target.register(
    "freenove-esp32-s3-wroom",
    isa: EspIdfBinding::XTENSA_LX7_S3, substrate: Substrate::BARE_METAL,
    binding: EspIdfBinding, machine: Machine.register(:esp32_s3_wroom, chip: "esp32s3")
  )
end
