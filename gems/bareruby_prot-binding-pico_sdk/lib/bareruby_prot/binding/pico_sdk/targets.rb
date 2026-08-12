# frozen_string_literal: true

require_relative "binding"
require_relative "build"
require_relative "toolchain"
require_relative "flash"

# What this binding brings: the machines it reaches, and the compositions it can produce
# for them. Everything the compiler knows about them arrives from here.
#
# One SDK, four boards, two instruction sets. The chip is a fact about the board and the
# triple is a fact about the composition, which is why a second chip is a line here rather
# than a second back end — one first stage over the same program produces both.
module BareRubyProt
  module PicoSdkBinding
    CORTEX_M0PLUS = Isa.new("thumbv6m-none-eabi")
    CORTEX_M33 = Isa.new("thumbv8m.main-none-eabihf")
  end

  Target.register(
    "raspberry-pi-pico",
    isa: PicoSdkBinding::CORTEX_M0PLUS, substrate: Substrate::BARE_METAL,
    binding: PicoSdkBinding, machine: Machine.register(:pico, chip: "rp2040")
  )

  Target.register(
    "raspberry-pi-pico-w",
    isa: PicoSdkBinding::CORTEX_M0PLUS, substrate: Substrate::BARE_METAL,
    binding: PicoSdkBinding, machine: Machine.register(:pico_w, chip: "rp2040")
  )

  Target.register(
    "raspberry-pi-pico2",
    isa: PicoSdkBinding::CORTEX_M33, substrate: Substrate::BARE_METAL,
    binding: PicoSdkBinding, machine: Machine.register(:pico2, chip: "rp2350")
  )

  Target.register(
    "raspberry-pi-pico2-w",
    isa: PicoSdkBinding::CORTEX_M33, substrate: Substrate::BARE_METAL,
    binding: PicoSdkBinding, machine: Machine.register(:pico2_w, chip: "rp2350")
  )
end
