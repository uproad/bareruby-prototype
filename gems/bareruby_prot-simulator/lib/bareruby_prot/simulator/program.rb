# frozen_string_literal: true

module BareRubyProt
  module Simulator
    # The artifact a build left, read the way a loader reads one: the segments meant to be
    # in memory are put there, the relocations the linker left for load time are applied,
    # and every name the program defined or asked for is answered from the tables it
    # carries.
    #
    # **The names are the whole reason this is read rather than run.** A peripheral call
    # is an ordinary call to an ordinary function here, so knowing where that function
    # begins is knowing where to put a board instead of it.
    #
    # It is a position-independent executable, so where it lands is this side's choice.
    # `BASE` is that choice, and nothing about it matters except that it is not zero: a
    # null pointer has to stay distinguishable from the first byte of the program.
    class Program
      BASE = 0x40_0000

      PT_LOAD = 1

      PT_GNU_EH_FRAME = 0x6474_E550

      SHT_SYMTAB = 2
      SHT_RELA = 4
      SHT_DYNSYM = 11

      SHN_UNDEF = 0

      R_X86_64_64 = 1
      R_X86_64_GLOB_DAT = 6
      R_X86_64_JUMP_SLOT = 7
      R_X86_64_RELATIVE = 8

      Section = Data.define(:type, :offset, :size, :link, :entry_size)

      # One row of a symbol table. A row whose section is `SHN_UNDEF` is a name the
      # program asked for and did not define, which is exactly the row this side answers.
      Named = Data.define(:name, :value, :section) do
        def defined? = section != SHN_UNDEF
      end

      def initialize(path)
        @image = File.binread(path)
        @sections = sections
        @named = named(SHT_SYMTAB)
        @imports = named(SHT_DYNSYM)
      end

      # Where a name the program defined begins, as an address in the running image.
      def address_of(name)
        found = @named.find { |row| row.name == name && row.defined? }
        found && BASE + found.value
      end

      # Every name the program defined, by address. What a call lands on is looked up in
      # this, so it answers the question the other way round from `address_of`.
      def defined
        @named.each_with_object({}) do |row, found|
          found[BASE + row.value] = row.name if row.defined?
        end
      end

      # Only the file part of each segment is written: a page nobody has written to
      # already reads as zero, which is exactly what the rest of a segment larger than
      # its file has to be.
      def load(memory)
        each_segment do |offset, address, file_size|
          memory.write(BASE + address, @image.byteslice(offset, file_size))
        end
      end

      # Where the table that says how to unwind from an address begins. It is found as a
      # program header rather than as a section, because a section is named and a name is
      # one more table to read.
      def unwinding
        headers { |type, _offset, address| return BASE + address if type == PT_GNU_EH_FRAME }
      end

      # What the linker left for load time. A name the program asked for and nobody
      # defined is answered by whoever calls this — which is where a peripheral, and the
      # C library, get their addresses from.
      def relocate(memory)
        each_relocation do |type, offset, index, addend|
          where = BASE + offset
          case type
          when R_X86_64_RELATIVE then memory.write64(where, BASE + addend)
          when R_X86_64_GLOB_DAT, R_X86_64_JUMP_SLOT, R_X86_64_64
            row = @imports[index]
            memory.write64(where, row.defined? ? BASE + row.value + addend : (yield(row.name) || 0))
          end
        end
      end

      private

      def each_segment
        headers do |type, offset, address, size|
          yield(offset, address, size) if type == PT_LOAD
        end
      end

      def headers
        offset = quad(0x20)
        half(0x38).times do |index|
          at = offset + (index * half(0x36))
          yield(word(at), quad(at + 0x08), quad(at + 0x10), quad(at + 0x20))
        end
      end

      def each_relocation
        @sections.select { |section| section.type == SHT_RELA }.each do |section|
          (section.size / section.entry_size).times do |index|
            at = section.offset + (index * section.entry_size)
            info = quad(at + 8)
            yield(info & 0xFFFF_FFFF, quad(at), info >> 32, signed(quad(at + 16)))
          end
        end
      end

      def sections
        offset = quad(0x28)
        Array.new(half(0x3C)) do |index|
          at = offset + (index * half(0x3A))
          Section.new(type: word(at + 4), offset: quad(at + 0x18), size: quad(at + 0x20),
                      link: word(at + 0x28), entry_size: quad(at + 0x38))
        end
      end

      def named(kind)
        table = @sections.find { |section| section.type == kind }
        strings = @sections[table.link]
        Array.new(table.size / table.entry_size) do |index|
          at = table.offset + (index * table.entry_size)
          Named.new(name: string(strings.offset + word(at)), value: quad(at + 8),
                    section: half(at + 6))
        end
      end

      def string(at) = @image.byteslice(at, @image.index("\0", at) - at)

      def signed(value) = value >= (1 << 63) ? value - (1 << 64) : value

      def half(at) = @image.unpack1("v", offset: at)

      def word(at) = @image.unpack1("V", offset: at)

      def quad(at) = @image.unpack1("Q<", offset: at)
    end
  end
end
