# frozen_string_literal: true

require_relative "binding"
require_relative "machine"
require_relative "system"
require_relative "unwinding"

module BareRubyProt
  module Simulator
    # One run of one artifact: the binding that interprets it, the machine it runs
    # against, and the C library underneath. Holding the three together is what lets a run
    # be read after it has finished — the machine is still there, with everything on it
    # where the program left it.
    #
    # **Nothing here reads the desk's clock or the desk's speed.** A wait moves virtual
    # time and nothing else, so two runs of one artifact leave the machine in the same
    # state, which is what makes it something a check can be written against.
    class Run
      attr_reader :machine, :system, :clock

      def initialize(artifact, seconds: 3, out: $stdout, err: $stderr, input: nil)
        @clock = Clock.new(seconds)
        @binding = Binding.new(artifact, clock: @clock)
        @machine = Machine.new(clock: @clock, wire: input)
        @system = System.new(out: out, err: err, input: input)
        @unwinding = Unwinding.new(@binding.memory, @binding.unwinding)
        @binding.prepare(@machine.calls.merge(@system.calls, @unwinding.calls),
                         @system.values(@binding).merge(@unwinding.values))
        @machine.attach(@binding)
      end

      # The program from its entry point until it returns, or until the time it was given
      # runs out. A firmware never returns, which is why the second of those exists.
      #
      # A block given here runs every time the program waits, holding the machine: that is
      # when a caller gets to move an input, and it is the same moment a machine would
      # deliver an interrupt.
      def start(&waiting)
        @machine.while_waiting(&waiting) if waiting
        @binding.run("main")
        self
      end

      def status = @system.status

      # What to do between one instruction and the next — a step, in the unit the clock
      # counts in. See `Binding#while_stepping`.
      def while_stepping(&watching) = @binding.while_stepping(&watching)

      # How many instructions were interpreted. What a run cost, in the only unit this
      # side has one in.
      def instructions = @binding.instructions

      # Whether the run ended by itself rather than by running out of time.
      def finished? = !@clock.over?
    end
  end
end
