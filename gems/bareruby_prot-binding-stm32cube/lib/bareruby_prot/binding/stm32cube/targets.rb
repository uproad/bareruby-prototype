# frozen_string_literal: true

require_relative "binding"

# What this binding brings: every board the two manifest layers describe, registered as
# a target. Nothing is listed here — a board arrives by being described, whether the
# description sits in this gem's data/ or in a project's config/stm32cube/, and the
# compiler learns it the same way either way.
module BareRubyProt
  module Stm32CubeBinding
    # An instruction set is a fact of the core and its FPU, so it is derived rather
    # than asked of every device manifest — one table, extended when a family brings a
    # pair it does not hold. The absence of an FPU is spelled `none` in a manifest.
    TRIPLES = {
      ["cortex-m0", nil] => "thumbv6m-none-eabi",
      ["cortex-m0plus", nil] => "thumbv6m-none-eabi",
      ["cortex-m4", "fpv4-sp-d16"] => "thumbv7em-none-eabihf",
      ["cortex-m7", "fpv5-sp-d16"] => "thumbv7em-none-eabihf",
      ["cortex-m7", "fpv5-d16"] => "thumbv7em-none-eabihf"
    }.freeze

    def self.isa(device)
      fpu = device.fpu == "none" ? nil : device.fpu
      triple = TRIPLES.fetch([device.core, fpu]) do
        raise Manifests::Error.new(device.path,
                                   "no triple is known for #{device.core} with #{device.fpu}")
      end
      (@isas ||= {})[triple] ||= Isa.new(triple)
    end
  end

  Stm32CubeBinding::Manifests.boards.each do |board|
    device = board.device
    Target.register(
      board.name,
      isa: Stm32CubeBinding.isa(device), substrate: Substrate::BARE_METAL,
      binding: Stm32CubeBinding,
      machine: Machine.register(board.key.to_sym, chip: device.part)
    )
  end
end
