# frozen_string_literal: true

require_relative "binding"
require_relative "build"
require_relative "toolchain"
require_relative "flash"

# What this binding brings: the machines it reaches, and the compositions it can produce
# for them. Everything the compiler knows about them arrives from here.
module BareRubyProt
  module Stm32CubeBinding
    CORTEX_M4F = Isa.new("thumbv7em-none-eabihf")
  end

  Target.register(
    "stm32-nucleo-f446re", short: "f446",
    isa: Stm32CubeBinding::CORTEX_M4F, substrate: Substrate::BARE_METAL,
    binding: Stm32CubeBinding, machine: Machine.register(:nucleo_f446re, chip: "stm32f446re")
  )
end
