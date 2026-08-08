# frozen_string_literal: true

require_relative "binding"
require_relative "build"
require_relative "flash"

# What this binding brings: the machines it reaches, and the compositions it can produce
# for them. Everything the compiler knows about them arrives from here.
#
# The machine doing the compiling has no peripheral to reach, so every binding call lands
# on a stub. It is still a machine, and saying so keeps the hosted target from being a
# shape of its own — the same answer serves a target that runs in a sandbox rather than on
# a board. Its instruction set is whatever this desk is, because a hosted build is not one
# machine: the same source compiled elsewhere is another triple entirely.
module BareRubyProt
  Target.register(
    "host",
    isa: Isa::COMPILING,
    substrate: Substrate::HOSTED,
    binding: HostBinding,
    machine: Machine.register(:none)
  )
end
