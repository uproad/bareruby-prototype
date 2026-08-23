# frozen_string_literal: true

module BareRubyProt
  module Simulator
    # The address space the program runs in, one page at a time. A page nobody has
    # written to reads as zero, which is what makes loading a segment whose memory is
    # larger than its file nothing more than writing the file part: the rest is already
    # what it has to be.
    class Memory
      PAGE = 0x1000

      def initialize
        @pages = Hash.new { |pages, index| pages[index] = ("\0" * PAGE).b }
      end

      def read(address, length)
        bytes = +""
        until length.zero?
          index, offset = address.divmod(PAGE)
          taken = [length, PAGE - offset].min
          bytes << @pages[index].byteslice(offset, taken)
          address += taken
          length -= taken
        end
        bytes
      end

      def write(address, bytes)
        written = 0
        while written < bytes.bytesize
          index, offset = (address + written).divmod(PAGE)
          taken = [bytes.bytesize - written, PAGE - offset].min
          @pages[index][offset, taken] = bytes.byteslice(written, taken)
          written += taken
        end
      end

      # What a C string is: bytes up to the first zero, which is not part of it.
      def string(address)
        bytes = +""
        loop do
          index, offset = address.divmod(PAGE)
          page = @pages[index]
          ending = page.index("\0", offset)
          return bytes << page.byteslice(offset, ending - offset) if ending

          bytes << page.byteslice(offset, PAGE - offset)
          address = (index + 1) * PAGE
        end
      end

      def read8(address) = read(address, 1).unpack1("C")

      def read16(address) = read(address, 2).unpack1("v")

      def read32(address) = read(address, 4).unpack1("V")

      def read64(address) = read(address, 8).unpack1("Q<")

      def write8(address, value) = write(address, [value & 0xFF].pack("C"))

      def write16(address, value) = write(address, [value & 0xFFFF].pack("v"))

      def write32(address, value) = write(address, [value & 0xFFFF_FFFF].pack("V"))

      def write64(address, value) = write(address, [value & MASK].pack("Q<"))

      MASK = 0xFFFF_FFFF_FFFF_FFFF
    end
  end
end
