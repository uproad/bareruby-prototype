# frozen_string_literal: true

require_relative "simulator/run"

module BareRubyProt
  # A host build run interpreted rather than executed: the instructions are read here, and
  # every call a program makes into a peripheral lands on an object instead of on a stub
  # that prints what it was asked.
  #
  # **What that buys is a machine that is still there afterwards.** A trace says a pin was
  # written; a `Gpio` says what the pin is at, how often it changed, and which way it was
  # set up — so a display can show it and a check can read it. The whole of that is
  # `Run#machine`, and [`API.md`](../../API.md) is what it answers.
  module Simulator
    def self.run(artifact, seconds: 3, out: $stdout, err: $stderr, input: nil, &waiting)
      Run.new(artifact, seconds: seconds, out: out, err: err, input: input).start(&waiting)
    end
  end
end
