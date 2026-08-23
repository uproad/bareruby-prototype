# frozen_string_literal: true

module BareRubyProt
  module Simulator
    # Turning a C format string into what it prints. Both sides of this simulator need
    # it — the C library, and a serial port a program writes to with `printf` — so it is
    # written once and mixed into each.
    #
    # It is rendered one conversion at a time rather than handed to Ruby whole, because
    # the argument each conversion takes is as wide as its length modifier says, and
    # Ruby's own `format` has no length to be told.
    module Formatting
      # The flags and width Ruby spells the same way, the length that says how wide the
      # argument is, and the letter that says what it is.
      CONVERSION = /%([-+ #0]*\d*(?:\.\d+)?)(hh|h|ll|l|z|j|t)?([diouxXcsp%])/

      SIGNED = %w[d i].freeze

      NARROW = [nil, "hh", "h"].freeze

      def rendered(binding, pointer, arguments)
        binding.string(pointer).gsub(CONVERSION) do
          spelling = ::Regexp.last_match(1)
          length = ::Regexp.last_match(2)
          kind = ::Regexp.last_match(3)
          next "%" if kind == "%"

          format("%#{spelling}#{kind == 'p' ? 'x' : kind}",
                 converted(binding, kind, length, arguments.take))
        end
      end

      def converted(binding, kind, length, raw)
        return binding.string(raw) if kind == "s"
        return raw & 0xFF if kind == "c"

        bits = NARROW.include?(length) ? 32 : 64
        value = raw & ((1 << bits) - 1)
        SIGNED.include?(kind) && value >= (1 << (bits - 1)) ? value - (1 << bits) : value
      end

      # The arguments of a call that takes as many as it was given, in the registers and
      # then on the stack the calling convention names.
      class Passed
        def initialize(binding, first)
          @binding = binding
          @index = first
        end

        def take
          value = @binding.argument(@index)
          @index += 1
          value
        end
      end

      # The same arguments reached the other way: a `va_list` the caller built, which is
      # a cursor into the block of registers a variadic function saved on entry, and then
      # into whatever would not fit in them.
      class Varying
        REGISTERS = 48

        def initialize(binding, pointer)
          @memory = binding.memory
          @pointer = pointer
        end

        def take
          offset = @memory.read32(@pointer)
          return from_overflow if offset >= REGISTERS

          @memory.write32(@pointer, offset + 8)
          @memory.read64(@memory.read64(@pointer + 16) + offset)
        end

        private

        def from_overflow
          where = @memory.read64(@pointer + 8)
          @memory.write64(@pointer + 8, where + 8)
          @memory.read64(where)
        end
      end
    end
  end
end
