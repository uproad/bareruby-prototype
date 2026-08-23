# frozen_string_literal: true

require_relative "formatting"

module BareRubyProt
  module Simulator
    # The C library, answered in Ruby. **Only what the artifact actually asks for**: a
    # build here leaves about thirty undefined names, and printing is most of them.
    #
    # The streams are given addresses of this side's choosing. `stdout` is a name whose
    # value is a pointer, so two levels are needed — the storage the name is, and the
    # stream it points at — and both are made up here, because nothing on this side is a
    # file.
    class System
      include Formatting

      HOLDERS = 0x2000_0000
      STREAMS = 0x2000_0100

      IN = STREAMS
      OUT = STREAMS + 0x10
      ERR = STREAMS + 0x20

      NAMES = %w[stdin stdout stderr].freeze

      # What a failing read answers, and what a call answers when it has nothing to say:
      # an all-ones word, read back as -1 at whatever width the caller asked in.
      REFUSED = 0xFFFF_FFFF_FFFF_FFFF

      attr_reader :status

      def initialize(out:, err:, input:)
        @out = out
        @err = err
        @input = input
        @status = 0
      end

      # The addresses the three stream names hold, written into memory so that reading
      # one gives back a stream the way reading it in C would.
      def values(machine)
        NAMES.each_with_index.to_h do |name, index|
          machine.memory.write64(HOLDERS + (index * 8), STREAMS + (index * 0x10))
          [name, HOLDERS + (index * 8)]
        end
      end

      def calls
        {
          "printf" => method(:print_out), "vprintf" => method(:print_varying),
          "fprintf" => method(:print_stream), "snprintf" => method(:print_buffer),
          "vsnprintf" => method(:print_buffer_varying), "puts" => method(:put_line),
          "fwrite" => method(:write_stream), "fputc" => method(:put_byte),
          "fputs" => method(:put_string), "fflush" => method(:answer_zero),
          "fgetc" => method(:get_byte), "read" => method(:read_bytes),
          "fcntl" => method(:answer_zero), "memcpy" => method(:copy),
          "strlen" => method(:length), "strcmp" => method(:compare),
          "clock_gettime" => method(:answer_zero), "exit" => method(:leave),
          "__stack_chk_fail" => method(:leave)
        }
      end

      private

      # ---- printing -------------------------------------------------------------

      def print_out(machine)
        write(OUT, rendered(machine, machine.argument(0), Passed.new(machine, 1)))
      end

      def print_varying(machine)
        arguments = Varying.new(machine, machine.argument(1))
        write(OUT, rendered(machine, machine.argument(0), arguments))
      end

      def print_stream(machine)
        arguments = Passed.new(machine, 2)
        write(machine.argument(0), rendered(machine, machine.argument(1), arguments))
      end

      def print_buffer(machine) = filled(machine, Passed.new(machine, 3))

      def print_buffer_varying(machine)
        filled(machine, Varying.new(machine, machine.argument(3)))
      end

      def filled(machine, arguments)
        text = rendered(machine, machine.argument(2), arguments)
        kept = text.byteslice(0, machine.argument(1) - 1)
        machine.memory.write(machine.argument(0), "#{kept}\0")
        machine.answer(text.bytesize)
      end

      def put_line(machine) = write(OUT, "#{machine.string(machine.argument(0))}\n")

      def put_string(machine)
        write(machine.argument(1), machine.string(machine.argument(0)))
      end

      def write_stream(machine)
        length = machine.argument(1) * machine.argument(2)
        write(machine.argument(3), machine.bytes(machine.argument(0), length))
        machine.answer(machine.argument(2))
      end

      def put_byte(machine)
        write(machine.argument(1), (machine.argument(0) & 0xFF).chr)
        machine.answer(machine.argument(0))
      end

      def write(stream, bytes) = (stream == ERR ? @err : @out).write(bytes)

      # ---- the rest -------------------------------------------------------------

      def get_byte(machine) = machine.answer(@input&.getbyte || REFUSED)

      def read_bytes(machine)
        arrived = @input&.read_nonblock(machine.argument(2), exception: false)
        return machine.answer(REFUSED) unless arrived.is_a?(String)

        machine.memory.write(machine.argument(1), arrived)
        machine.answer(arrived.bytesize)
      end

      def copy(machine)
        machine.memory.write(machine.argument(0),
                             machine.memory.read(machine.argument(1), machine.argument(2)))
        machine.answer(machine.argument(0))
      end

      def length(machine) = machine.answer(machine.string(machine.argument(0)).bytesize)

      def compare(machine)
        left = machine.string(machine.argument(0))
        machine.answer((left <=> machine.string(machine.argument(1))) & 0xFFFF_FFFF)
      end

      def answer_zero(machine) = machine.answer(0)

      def leave(machine)
        @status = machine.argument(0) & 0xFF
        machine.stop
      end
    end
  end
end
