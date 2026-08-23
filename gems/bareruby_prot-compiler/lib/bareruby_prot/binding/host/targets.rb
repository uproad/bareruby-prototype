# frozen_string_literal: true

require_relative "binding"
require_relative "build"
require_relative "emulate"
require_relative "flash"

# What this binding brings: the machines it reaches, and the compositions it can produce
# for them. Everything the compiler knows about them arrives from here.
#
# **The machine doing the compiling is a machine**, and this binding reaches exactly one.
# It was written down as `none` while the only thing behind a call was a line on fd2, but
# a call arrives somewhere here as much as anywhere else: the simulator is where it
# arrives, and it has pins, ports and an indicator. Its instruction set is whatever this
# desk is, because a hosted build is not one machine — the same source compiled elsewhere
# is another triple entirely.
module BareRubyProt
  Target.register(
    "host",
    isa: Isa::COMPILING,
    substrate: Substrate::HOSTED,
    binding: HostBinding,
    machine: Machine.register(:host)
  )
end
