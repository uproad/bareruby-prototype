# frozen_string_literal: true

require "rbconfig"

module BareRubyProt
  # The instruction set an artifact runs on, named by the target triple every toolchain
  # already agrees on. Nothing branches on this yet — one word size and one calling
  # convention have served every target so far — but the triple is recorded because it
  # settles the questions a second architecture disagrees about first: how wide a pointer
  # is, how a variadic argument promotes, and whether a 32-bit integer is the natural one.
  # An eight-bit machine and a machine whose instruction set is WebAssembly are both
  # reached by naming a different triple, not by adding a kind of target.
  class Isa
    attr_reader :triple

    def initialize(triple) = @triple = triple

    # The machine doing the compiling names itself, because a hosted build is not one
    # machine: the same source compiled on another desk is another triple entirely.
    COMPILING = new(RbConfig::CONFIG["host"])

    CORTEX_M0PLUS = new("thumbv6m-none-eabi")
    CORTEX_M33 = new("thumbv8m.main-none-eabihf")
    CORTEX_M4F = new("thumbv7em-none-eabihf")

    # The first instruction set here whose natural word is not 32 bits: an int is 16 bits
    # and a pointer is 16 bits, while an int32_t is a long. The triple names no chip,
    # because it does not settle one — an ATmega328P and an ATmega2560 are both this, and
    # which of them a build is for is said with -mmcu= further down.
    AVR = new("avr-none")
  end
end
