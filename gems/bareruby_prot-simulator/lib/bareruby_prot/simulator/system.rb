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
      def values(binding)
        NAMES.each_with_index.to_h do |name, index|
          binding.memory.write64(HOLDERS + (index * 8), STREAMS + (index * 0x10))
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

      def print_out(binding)
        write(OUT, rendered(binding, binding.argument(0), Passed.new(binding, 1)))
      end

      def print_varying(binding)
        arguments = Varying.new(binding, binding.argument(1))
        write(OUT, rendered(binding, binding.argument(0), arguments))
      end

      def print_stream(binding)
        arguments = Passed.new(binding, 2)
        write(binding.argument(0), rendered(binding, binding.argument(1), arguments))
      end

      def print_buffer(binding) = filled(binding, Passed.new(binding, 3))

      def print_buffer_varying(binding)
        filled(binding, Varying.new(binding, binding.argument(3)))
      end

      def filled(binding, arguments)
        text = rendered(binding, binding.argument(2), arguments)
        kept = text.byteslice(0, binding.argument(1) - 1)
        binding.memory.write(binding.argument(0), "#{kept}\0")
        binding.answer(text.bytesize)
      end

      def put_line(binding) = write(OUT, "#{binding.string(binding.argument(0))}\n")

      def put_string(binding)
        write(binding.argument(1), binding.string(binding.argument(0)))
      end

      def write_stream(binding)
        length = binding.argument(1) * binding.argument(2)
        write(binding.argument(3), binding.bytes(binding.argument(0), length))
        binding.answer(binding.argument(2))
      end

      def put_byte(binding)
        write(binding.argument(1), (binding.argument(0) & 0xFF).chr)
        binding.answer(binding.argument(0))
      end

      def write(stream, bytes) = (stream == ERR ? @err : @out).write(bytes)

      # ---- the rest -------------------------------------------------------------

      def get_byte(binding) = binding.answer(@input&.getbyte || REFUSED)

      def read_bytes(binding)
        arrived = @input&.read_nonblock(binding.argument(2), exception: false)
        return binding.answer(REFUSED) unless arrived.is_a?(String)

        binding.memory.write(binding.argument(1), arrived)
        binding.answer(arrived.bytesize)
      end

      def copy(binding)
        binding.memory.write(binding.argument(0),
                             binding.memory.read(binding.argument(1), binding.argument(2)))
        binding.answer(binding.argument(0))
      end

      def length(binding) = binding.answer(binding.string(binding.argument(0)).bytesize)

      def compare(binding)
        left = binding.string(binding.argument(0))
        binding.answer((left <=> binding.string(binding.argument(1))) & 0xFFFF_FFFF)
      end

      def answer_zero(binding) = binding.answer(0)

      def leave(binding)
        @status = binding.argument(0) & 0xFF
        binding.stop
      end
    end
  end
end
