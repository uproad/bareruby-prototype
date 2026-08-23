# frozen_string_literal: true

require_relative "board"
require_relative "machine"
require_relative "system"
require_relative "unwinding"

module BareRubyProt
  module Simulator
    # One run of one artifact: the machine that interprets it, the board it runs against,
    # and the C library underneath. Holding the three together is what lets a run be read
    # after it has finished — the board is still there, with everything on it where the
    # program left it.
    #
    # **Nothing here reads the desk's clock or the desk's speed.** A wait moves virtual
    # time and nothing else, so two runs of one artifact leave identical boards, which is
    # what makes a board something a check can be written against.
    class Run
      attr_reader :board, :machine, :system, :clock

      def initialize(artifact, seconds: 3, out: $stdout, err: $stderr, input: nil)
        @clock = Clock.new(seconds)
        @machine = Machine.new(artifact, clock: @clock)
        @board = Board.new(clock: @clock, wire: input)
        @system = System.new(out: out, err: err, input: input)
        @unwinding = Unwinding.new(@machine.memory, @machine.unwinding)
        @machine.prepare(@board.calls.merge(@system.calls, @unwinding.calls),
                         @system.values(@machine).merge(@unwinding.values))
        @board.attach(@machine)
      end

      # The program from its entry point until it returns, or until the time it was given
      # runs out. A firmware never returns, which is why the second of those exists.
      #
      # A block given here runs every time the program waits, holding the board: that is
      # when a caller gets to move an input, and it is the same moment a board would
      # deliver an interrupt.
      def start(&waiting)
        @board.while_waiting(&waiting) if waiting
        @machine.run("main")
        self
      end

      def status = @system.status

      # Whether the run ended by itself rather than by running out of time.
      def finished? = !@clock.over?
    end
  end
end
