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
  #
  # Only the machine doing the compiling is named here. Every other triple arrives with
  # the binding that reaches machines running it — an instruction set nothing here can be
  # built for is not this side's to know.
  class Isa
    attr_reader :triple

    def initialize(triple) = @triple = triple

    # The machine doing the compiling names itself, because a hosted build is not one
    # machine: the same source compiled on another desk is another triple entirely.
    COMPILING = new(RbConfig::CONFIG["host"])
  end
end
