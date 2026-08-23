# frozen_string_literal: true

require_relative "cpu"

module BareRubyProt
  module Simulator
    # Throwing, and getting back out. The four names a C++ throw reaches for are answered
    # here, and the middle one of them — the throw itself — is the only call in this
    # simulator that does not return to where it was called from.
    #
    # **The frames are walked rather than reconstructed.** The unwinder a program would
    # normally link against rebuilds each frame from the call frame information, because
    # optimized code keeps no frame pointer to walk. This build has one in every frame —
    # nothing here is compiled with an optimization level — so the chain of saved base
    # pointers is the call stack, and reading it is the whole of the walk.
    #
    # What still has to be read is where each frame would catch: that is in the tables
    # the compiler emits beside the code, and those say nothing about frames. So the
    # walk is this side's and the tables are the compiler's, which is the least of both.
    class Unwinding
      # The program header that says where the table mapping an address to its frame
      # begins.
      HEADER = 0x6474_E550

      # A made-up address for the one type this ever throws. Nothing compares against it:
      # every catch this compiler emits is a catch-all, so what is thrown is never asked
      # what it is.
      TYPE = 0x3000_0000

      OMITTED = 0xFF

      # How much of an address a run ever throws: a pointer, and nothing around it.
      OBJECT = 8

      def initialize(memory, header)
        @memory = memory
        @header = header
      end

      def calls
        {
          "__cxa_allocate_exception" => method(:allocated),
          "__cxa_throw" => method(:thrown),
          "__cxa_begin_catch" => method(:caught),
          "__cxa_end_catch" => method(:finished),
          "_Unwind_Resume" => method(:resumed)
        }
      end

      def values = { "_ZTIPKc" => TYPE }

      private

      def allocated(binding) = binding.answer(binding.place("\0" * OBJECT))

      def caught(binding) = binding.answer(binding.memory.read64(binding.argument(0)))

      def finished(binding) = binding.answer(0)

      def thrown(binding) = unwind(binding, binding.argument(0))

      def resumed(binding) = unwind(binding, binding.argument(0))

      # Up the chain of saved base pointers, one frame at a time, until one of them says
      # it has somewhere to land. A run that gets to the top without finding one is a
      # program with nothing to catch what it threw, and it ends there.
      def unwind(binding, object)
        frame = binding.cpu.register(Cpu::RBP)
        while frame.positive?
          returning = @memory.read64(frame + 8)
          break if returning == Binding::SENTINEL

          found = landing_pad(returning - 1)
          return land(binding, found, object, frame) if found

          frame = @memory.read64(frame)
        end
        binding.stop
      end

      # A landing pad runs in the frame that is catching, so the frame that threw is left
      # behind: the stack pointer goes back to what it was before the call, and the two
      # registers the pad reads are the object and which catch matched.
      def land(binding, found, object, frame)
        binding.cpu.set_register(Cpu::RAX, object)
        binding.cpu.set_register(Cpu::RDX, found.last)
        binding.cpu.set_register(Cpu::RSP, frame + 16)
        binding.cpu.set_register(Cpu::RBP, @memory.read64(frame))
        binding.resume(found.first)
      end

      # ---- the tables the compiler left -----------------------------------------

      def landing_pad(address)
        frame = frame_for(address)
        return nil unless frame

        begins, lsda = described(frame)
        return nil unless lsda

        caught_at(lsda, begins, address)
      end

      # The search table beside the frames: pairs of an address and the frame that
      # covers it, sorted, so the frame is found rather than looked for.
      def frame_for(address)
        low = 0
        high = @memory.read32(@header + 8) - 1
        found = nil
        while low <= high
          middle = (low + high) / 2
          at = @header + 12 + (middle * 8)
          if @header + signed(@memory.read32(at)) <= address
            found = at
            low = middle + 1
          else
            high = middle - 1
          end
        end
        found && @header + signed(@memory.read32(found + 4))
      end

      # Where the frame's code begins, and where what it catches is written down.
      def described(frame)
        reading = Reading.new(@memory, frame)
        reading.u32
        offset = reading.u32
        encodings = encodings_of(reading.at - 4 - offset)
        begins = decoded(reading, encodings.fetch(:frame))
        value(reading, encodings.fetch(:frame))
        reading.uleb
        [begins, decoded(reading, encodings.fetch(:catches))]
      end

      # Every frame in one build shares these, so they are read from the entry the frame
      # points back at rather than repeated in each frame.
      def encodings_of(at)
        reading = Reading.new(@memory, at)
        reading.u32
        reading.u32
        reading.u8
        letters = reading.string
        3.times { reading.uleb }
        found = { frame: 0x00, catches: OMITTED }
        return found unless letters.start_with?("z")

        reading.uleb
        letters.delete_prefix("z").each_char { |letter| augmentation(reading, letter, found) }
        found
      end

      def augmentation(reading, letter, found)
        case letter
        when "P" then decoded(reading, reading.u8)
        when "L" then found[:catches] = reading.u8
        when "R" then found[:frame] = reading.u8
        end
      end

      # Which call site the address falls in, and where that one lands. A site with no
      # pad is a call this frame does not catch around, which is not the same as a frame
      # that catches nothing — the walk stops either way, one frame further along.
      def caught_at(lsda, begins, address)
        reading = Reading.new(@memory, lsda)
        pads = pads_from(reading, begins)
        sites = site_encoding(reading)
        ending = reading.at + reading.uleb
        while reading.at < ending
          start = value(reading, sites)
          length = value(reading, sites)
          pad = value(reading, sites)
          action = reading.uleb
          next unless (start...(start + length)).cover?(address - begins)

          return pad.zero? ? nil : [pads + pad, action.zero? ? 0 : 1]
        end
        nil
      end

      def pads_from(reading, begins)
        encoding = reading.u8
        encoding == OMITTED ? begins : decoded(reading, encoding)
      end

      def site_encoding(reading)
        types = reading.u8
        reading.uleb unless types == OMITTED
        reading.u8
      end

      # ---- how a value is written down ------------------------------------------

      RELATIVE = 0x70

      PC = 0x10

      DATA = 0x30

      def decoded(reading, encoding)
        return nil if encoding == OMITTED

        at = reading.at
        found = value(reading, encoding)
        case encoding & RELATIVE
        when PC then at + found
        when DATA then @header + found
        else found
        end
      end

      def value(reading, encoding)
        case encoding & 0x0F
        when 0x01 then reading.uleb
        when 0x02 then reading.u16
        when 0x03 then reading.u32
        when 0x04 then reading.u64
        when 0x09 then reading.sleb
        when 0x0A then signed(reading.u16, 16)
        when 0x0B then signed(reading.u32)
        else reading.u64
        end
      end

      def signed(found, bits = 32)
        found >= (1 << (bits - 1)) ? found - (1 << bits) : found
      end

      # Reading a table forwards. Every one of these is written as a run of values whose
      # widths are only known as they are read, so where the next one starts is what has
      # to be carried along.
      class Reading
        attr_reader :at

        def initialize(memory, at)
          @memory = memory
          @at = at
        end

        def u8 = taken(1) { @memory.read8(@at) }

        def u16 = taken(2) { @memory.read16(@at) }

        def u32 = taken(4) { @memory.read32(@at) }

        def u64 = taken(8) { @memory.read64(@at) }

        def string
          found = @memory.string(@at)
          @at += found.bytesize + 1
          found
        end

        def uleb
          found = 0
          shift = 0
          loop do
            byte = u8
            found |= (byte & 0x7F) << shift
            return found unless byte.anybits?(0x80)

            shift += 7
          end
        end

        def sleb
          found = 0
          shift = 0
          loop do
            byte = u8
            found |= (byte & 0x7F) << shift
            shift += 7
            next if byte.anybits?(0x80)

            return byte.anybits?(0x40) ? found - (1 << shift) : found
          end
        end

        private

        def taken(width)
          found = yield
          @at += width
          found
        end
      end
    end
  end
end
