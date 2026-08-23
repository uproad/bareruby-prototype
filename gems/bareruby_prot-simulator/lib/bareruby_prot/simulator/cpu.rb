# frozen_string_literal: true

module BareRubyProt
  module Simulator
    # The instructions the compiling desk speaks, interpreted one at a time.
    #
    # **Only the ones this compiler emits.** A build here is a `g++` invocation with no
    # optimization level, over C++ written in a "better C" style: what comes out is
    # integer work, calls, and the occasional aligned move of a struct. There is no
    # floating point arithmetic in it anywhere — the wide moves below are how sixteen
    # bytes are copied and how a local is zeroed, and nothing here ever adds two of them.
    # An instruction that is not in this file is one this compiler has never emitted, and
    # meeting one is worth stopping over rather than stepping past.
    #
    # Four flags are kept, because four are set and read. Parity and the auxiliary carry
    # are computed by no instruction this reads and tested by none either.
    class Cpu
      RAX = 0
      RCX = 1
      RDX = 2
      RSP = 4
      RBP = 5
      RSI = 6
      RDI = 7

      MASK = 0xFFFF_FFFF_FFFF_FFFF

      # Which operation the top five bits of an arithmetic opcode name, and which the
      # `reg` field names when the operand is an immediate. Carry-in and borrow-in are
      # left out: nothing this reads is compiled into a two-word addition.
      OPERATIONS = { 0 => :add, 1 => :or, 4 => :and, 5 => :sub, 6 => :xor, 7 => :cmp }.freeze

      # The two that answer with flags and keep their hands off the operand.
      COMPARISONS = %i[cmp test].freeze

      attr_accessor :rip, :fs_base
      attr_reader :memory

      def initialize(memory)
        @memory = memory
        @registers = Array.new(16, 0)
        @wide = Array.new(16, 0)
        @rip = 0
        @fs_base = 0
        @halted = false
        @zf = false
        @sf = false
        @cf = false
        @of = false
      end

      def halted? = @halted

      def register(index) = @registers[index]

      def set_register(index, value) = @registers[index] = value & MASK

      def push(value)
        @registers[RSP] = (@registers[RSP] - 8) & MASK
        @memory.write64(@registers[RSP], value)
      end

      def pop
        value = @memory.read64(@registers[RSP])
        @registers[RSP] = (@registers[RSP] + 8) & MASK
        value
      end

      # One instruction: the prefixes that change what it means, the opcode, and then
      # whatever that opcode says comes after it.
      def step
        @rex = nil
        @size = 4
        @segment = false
        @repeat = nil
        prefixes
        opcode = fetch8
        opcode = 0x100 | fetch8 if opcode == 0x0F
        perform(opcode)
      end

      private

      def prefixes
        loop do
          byte = @memory.read8(@rip)
          case byte
          when 0x66 then @size = 2
          when 0xF2, 0xF3 then @repeat = byte
          when 0x64 then @segment = true
          when 0x26, 0x2E, 0x36, 0x3E, 0x65, 0x67 then nil
          when 0x40..0x4F
            @rex = byte
            @size = 8 if byte.anybits?(0x08)
          else return
          end
          @rip += 1
        end
      end

      def wide? = @rex&.anybits?(0x08)

      def rex_r = @rex ? (@rex >> 2) & 1 : 0

      def rex_x = @rex ? (@rex >> 1) & 1 : 0

      def rex_b = @rex ? @rex & 1 : 0

      def fetch8
        byte = @memory.read8(@rip)
        @rip += 1
        byte
      end

      def fetch16
        value = @memory.read16(@rip)
        @rip += 2
        value
      end

      def fetch32
        value = @memory.read32(@rip)
        @rip += 4
        value
      end

      def fetch64
        value = @memory.read64(@rip)
        @rip += 8
        value
      end

      def fetch_signed8 = extend_sign(fetch8, 8)

      def fetch_signed32 = extend_sign(fetch32, 32)

      def extend_sign(value, bits) = value >= (1 << (bits - 1)) ? value - (1 << bits) : value

      def masked(value) = value & ((1 << bits) - 1)

      def bits = @size * 8

      # What an instruction of this size carries as an immediate: never more than four
      # bytes, and sign-extended when the operands are eight.
      def immediate
        case @size
        when 1 then fetch8
        when 2 then fetch16
        when 4 then fetch32
        else fetch_signed32 & MASK
        end
      end

      # ---- operands -------------------------------------------------------------

      # Which register, and which memory, this instruction is about. A memory operand
      # that counts from the instruction pointer is kept as a displacement and added up
      # when it is read, because what it counts from is the end of the instruction —
      # which is not known yet while the displacement itself is being read.
      #
      # **That is why every immediate below is read before the operand it acts on.**
      def modrm
        byte = fetch8
        @mod = byte >> 6
        @reg = ((byte >> 3) & 7) | (rex_r << 3)
        rm = byte & 7
        if @mod == 3
          @rm = rm | (rex_b << 3)
          @relative = nil
        else
          @rm = nil
          decode_address(rm)
        end
      end

      def decode_address(rm)
        @relative = nil
        if rm == 4
          sib
        elsif rm == 5 && @mod.zero?
          @relative = fetch_signed32
          @address = 0
        else
          @address = @registers[rm | (rex_b << 3)]
        end
        @address += displacement
      end

      def sib
        byte = fetch8
        index = ((byte >> 3) & 7) | (rex_x << 3)
        @address = index == 4 ? 0 : @registers[index] * (1 << (byte >> 6))
        @address += if (byte & 7) == 5 && @mod.zero?
                      fetch_signed32
                    else
                      @registers[(byte & 7) | (rex_b << 3)]
                    end
      end

      def displacement
        case @mod
        when 1 then fetch_signed8
        when 2 then fetch_signed32
        else 0
        end
      end

      def address
        where = @relative ? @rip + @relative : @address
        (@segment ? where + @fs_base : where) & MASK
      end

      # The one place the eight-bit registers differ: without a REX prefix, the four
      # above the stack pointer name the high byte of the first four instead.
      def byte_register(index)
        return (@registers[index - 4] >> 8) & 0xFF if @rex.nil? && index.between?(4, 7)

        @registers[index] & 0xFF
      end

      def set_byte_register(index, value)
        if @rex.nil? && index.between?(4, 7)
          kept = @registers[index - 4] & ~0xFF00
          @registers[index - 4] = kept | ((value & 0xFF) << 8)
        else
          @registers[index] = (@registers[index] & ~0xFF) | (value & 0xFF)
        end
      end

      def read_register(index)
        case @size
        when 1 then byte_register(index)
        when 2 then @registers[index] & 0xFFFF
        when 4 then @registers[index] & 0xFFFF_FFFF
        else @registers[index]
        end
      end

      # Writing four bytes clears the four above them; writing one or two leaves what was
      # there. That asymmetry is the machine's, not this file's.
      def write_register(index, value)
        case @size
        when 1 then set_byte_register(index, value)
        when 2 then @registers[index] = (@registers[index] & ~0xFFFF) | (value & 0xFFFF)
        when 4 then @registers[index] = value & 0xFFFF_FFFF
        else @registers[index] = value & MASK
        end
      end

      def read_memory(where)
        case @size
        when 1 then @memory.read8(where)
        when 2 then @memory.read16(where)
        when 4 then @memory.read32(where)
        else @memory.read64(where)
        end
      end

      def write_memory(where, value)
        case @size
        when 1 then @memory.write8(where, value)
        when 2 then @memory.write16(where, value)
        when 4 then @memory.write32(where, value)
        else @memory.write64(where, value)
        end
      end

      def read_rm = @rm ? read_register(@rm) : read_memory(address)

      def write_rm(value) = @rm ? write_register(@rm, value) : write_memory(address, value)

      def read_reg = read_register(@reg)

      def write_reg(value) = write_register(@reg, value)

      # ---- flags ----------------------------------------------------------------

      def negative?(value) = value.anybits?(1 << (bits - 1))

      def settled(result)
        @zf = result.zero?
        @sf = negative?(result)
        result
      end

      def logical(result)
        @cf = false
        @of = false
        settled(masked(result))
      end

      def added(left, right)
        result = left + right
        @cf = result > masked(-1)
        @of = negative?(left) == negative?(right) && negative?(masked(result)) != negative?(left)
        settled(masked(result))
      end

      def subtracted(left, right)
        result = left - right
        @cf = left < right
        @of = negative?(left) != negative?(right) && negative?(masked(result)) != negative?(left)
        settled(masked(result))
      end

      def compute(operation, left, right)
        case operation
        when :add then added(left, right)
        when :sub, :cmp then subtracted(left, right)
        when :and, :test then logical(left & right)
        when :or then logical(left | right)
        when :xor then logical(left ^ right)
        end
      end

      def stored?(operation) = !COMPARISONS.include?(operation)

      # ---- instructions ---------------------------------------------------------

      def perform(opcode)
        case opcode
        when 0x00..0x3D then arithmetic(opcode)
        when 0x50..0x57 then push(@registers[(opcode & 7) | (rex_b << 3)])
        when 0x58..0x5F then @registers[(opcode & 7) | (rex_b << 3)] = pop
        when 0x63 then widen_from_four
        when 0x68 then push(fetch_signed32 & MASK)
        when 0x69, 0x6B then multiply_by_immediate(opcode)
        when 0x6A then push(fetch_signed8 & MASK)
        when 0x70..0x7F then branch(opcode & 0xF, fetch_signed8)
        when 0x80, 0x81, 0x83 then arithmetic_by_immediate(opcode)
        when 0x84, 0x85 then compare_bits(opcode)
        when 0x86, 0x87 then exchange(opcode)
        when 0x88, 0x89 then move_to_rm(opcode)
        when 0x8A, 0x8B then move_to_reg(opcode)
        when 0x8D then lea
        when 0x90 then nil
        when 0x98 then widen_accumulator
        when 0x99 then extend_accumulator
        when 0xA4, 0xA5, 0xAA, 0xAB then repeated(opcode)
        when 0xA8, 0xA9 then compare_accumulator_bits(opcode)
        when 0xB0..0xB7 then load_byte(opcode)
        when 0xB8..0xBF then load_immediate(opcode)
        when 0xC0, 0xC1 then shift_by_immediate(opcode)
        when 0xC3 then @rip = pop
        when 0xC6, 0xC7 then move_immediate(opcode)
        when 0xC9 then leave
        when 0xD0, 0xD1 then shift_by(opcode, 1)
        when 0xD2, 0xD3 then shift_by(opcode, @registers[RCX] & 0xFF)
        when 0xE8 then call(fetch_signed32)
        when 0xE9 then jump(fetch_signed32)
        when 0xEB then jump(fetch_signed8)
        when 0xF4 then @halted = true
        when 0xF6, 0xF7 then unary(opcode)
        when 0xFE, 0xFF then indirect(opcode)
        else extended(opcode)
        end
      end

      # Every arithmetic opcode below 0x40 is one of six operations and one of six
      # operand forms, and the low three bits say which form. The even ones below the
      # last two are the byte-wide forms.
      def arithmetic(opcode)
        operation = OPERATIONS.fetch(opcode >> 3)
        form = opcode & 7
        @size = 1 if form.even? && form < 6
        case form
        when 0, 1 then to_rm(operation)
        when 2, 3 then to_reg(operation)
        else to_accumulator(operation)
        end
      end

      def to_rm(operation)
        modrm
        result = compute(operation, read_rm, read_reg)
        write_rm(result) if stored?(operation)
      end

      def to_reg(operation)
        modrm
        result = compute(operation, read_reg, read_rm)
        write_reg(result) if stored?(operation)
      end

      def to_accumulator(operation)
        result = compute(operation, read_register(RAX), immediate)
        write_register(RAX, result) if stored?(operation)
      end

      def arithmetic_by_immediate(opcode)
        @size = 1 if opcode == 0x80
        modrm
        operation = OPERATIONS.fetch(@reg)
        right = opcode == 0x83 ? (fetch_signed8 & masked(-1)) : immediate
        result = compute(operation, read_rm, right)
        write_rm(result) if stored?(operation)
      end

      def compare_bits(opcode)
        @size = 1 if opcode == 0x84
        modrm
        compute(:test, read_rm, read_reg)
      end

      def compare_accumulator_bits(opcode)
        @size = 1 if opcode == 0xA8
        compute(:test, read_register(RAX), immediate)
      end

      def move_to_rm(opcode)
        @size = 1 if opcode == 0x88
        modrm
        write_rm(read_reg)
      end

      def move_to_reg(opcode)
        @size = 1 if opcode == 0x8A
        modrm
        write_reg(read_rm)
      end

      def move_immediate(opcode)
        @size = 1 if opcode == 0xC6
        modrm
        write_rm(immediate)
      end

      def lea
        modrm
        write_reg(address)
      end

      def branch(condition, offset)
        jump(offset) if satisfied?(condition)
      end

      # **What an offset counts from is the end of the instruction**, so the fetch that
      # reads it has to happen before the pointer it moves is read. Writing that as
      # `@rip += fetch` would read the pointer first and lose the byte the fetch just
      # stepped over, which is a jump one byte short of where it was going.
      def jump(offset) = @rip += offset

      def satisfied?(condition)
        case condition
        when 0x0 then @of
        when 0x1 then !@of
        when 0x2 then @cf
        when 0x3 then !@cf
        when 0x4 then @zf
        when 0x5 then !@zf
        when 0x6 then @cf || @zf
        when 0x7 then !@cf && !@zf
        when 0x8 then @sf
        when 0x9 then !@sf
        when 0xC then @sf != @of
        when 0xD then @sf == @of
        when 0xE then @zf || (@sf != @of)
        else !@zf && (@sf == @of)
        end
      end

      def call(offset)
        push(@rip)
        jump(offset)
      end

      def leave
        @registers[RSP] = @registers[RBP]
        @registers[RBP] = pop
      end

      def exchange(opcode)
        @size = 1 if opcode == 0x86
        modrm
        left = read_rm
        write_rm(read_reg)
        write_reg(left)
      end

      def load_byte(opcode)
        @size = 1
        set_byte_register((opcode & 7) | (rex_b << 3), fetch8)
      end

      # The one instruction that carries a whole address as an immediate, and the same
      # opcode carrying four bytes when it does not.
      def load_immediate(opcode)
        index = (opcode & 7) | (rex_b << 3)
        return @registers[index] = fetch64 if @size == 8

        write_register(index, immediate)
      end

      def widen_accumulator
        @size = wide? ? 8 : 4
        write_register(RAX, extend_sign(@registers[RAX] & (wide? ? 0xFFFF_FFFF : 0xFFFF),
                                        wide? ? 32 : 16) & MASK)
      end

      # What a division needs above the dividend: the sign of it, in every bit.
      def extend_accumulator
        top = @size == 8 ? 63 : 31
        write_register(RDX, @registers[RAX].anybits?(1 << top) ? MASK : 0)
      end

      def widen_from_four
        modrm
        @size = 4
        value = read_rm
        @size = 8
        write_reg(extend_sign(value, 32) & MASK)
      end

      def multiply_by_immediate(opcode)
        modrm
        right = opcode == 0x6B ? (fetch_signed8 & masked(-1)) : immediate
        write_reg(multiplied(read_rm, right))
      end

      def multiplied(left, right)
        result = extend_sign(left, bits) * extend_sign(right, bits)
        @cf = result != extend_sign(masked(result), bits)
        @of = @cf
        masked(result)
      end

      def shift_by_immediate(opcode)
        @size = 1 if opcode == 0xC0
        modrm
        shift(fetch8)
      end

      def shift_by(opcode, count)
        @size = 1 if opcode.even?
        modrm
        shift(count)
      end

      def shift(count)
        count &= @size == 8 ? 0x3F : 0x1F
        return if count.zero?

        value = read_rm
        case @reg
        when 4 then shifted_left(value, count)
        when 5 then shifted_right(value, count)
        else shifted_arithmetic(value, count)
        end
      end

      def shifted_left(value, count)
        @cf = ((value >> (bits - count)) & 1) == 1
        write_rm(shifted(masked(value << count)))
      end

      def shifted_right(value, count)
        @cf = ((value >> (count - 1)) & 1) == 1
        write_rm(shifted(value >> count))
      end

      def shifted_arithmetic(value, count)
        signed = extend_sign(value, bits)
        @cf = ((signed >> (count - 1)) & 1) == 1
        write_rm(shifted(masked(signed >> count)))
      end

      # A shift leaves the carry it shifted out, so the rest are settled without it.
      def shifted(result)
        @of = false
        settled(result)
      end

      def unary(opcode)
        @size = 1 if opcode == 0xF6
        modrm
        case @reg
        when 0 then compare_immediate
        when 2 then write_rm(masked(~read_rm))
        when 3 then write_rm(subtracted(0, read_rm))
        when 4 then multiply(false)
        when 5 then multiply(true)
        else divide(@reg == 7)
        end
      end

      def compare_immediate
        right = immediate
        compute(:test, read_rm, right)
      end

      def multiply(signed)
        left = read_register(RAX)
        right = read_rm
        result = signed ? extend_sign(left, bits) * extend_sign(right, bits) : left * right
        write_register(RAX, result)
        write_register(RDX, result >> bits)
        @cf = (result >> bits) != 0
        @of = @cf
      end

      # Truncating division, which is the one C asks for and not the one Ruby's operators
      # answer with.
      def divide(signed)
        divisor = read_rm
        dividend = (read_register(RDX) << bits) | read_register(RAX)
        if signed
          divisor = extend_sign(divisor, bits)
          dividend = extend_sign(dividend, bits * 2)
        end
        quotient = dividend.abs / divisor.abs
        quotient = -quotient if dividend.negative? ^ divisor.negative?
        write_register(RAX, quotient)
        write_register(RDX, dividend - (quotient * divisor))
      end

      def indirect(opcode)
        @size = 1 if opcode == 0xFE
        modrm
        case @reg
        when 0 then write_rm(stepped(read_rm, 1))
        when 1 then write_rm(stepped(read_rm, -1))
        when 2 then call_through
        when 4 then @rip = pointer
        when 6 then push(pointer)
        end
      end

      # A call or a jump through memory is always about a whole address, whatever the
      # prefixes said the operands were.
      def pointer
        @size = 8
        read_rm
      end

      def call_through
        where = pointer
        push(@rip)
        @rip = where
      end

      # Stepping by one leaves the carry alone, which is the only reason it is not
      # `added` outright.
      def stepped(value, by)
        carry = @cf
        result = by.positive? ? added(value, 1) : subtracted(value, 1)
        @cf = carry
        result
      end

      def repeated(opcode)
        @size = 1 if opcode.even?
        count = @repeat ? @registers[RCX] : 1
        count.times { opcode < 0xAA ? move_string : store_string }
        @registers[RCX] = 0 if @repeat
      end

      def move_string
        @memory.write(@registers[RDI], @memory.read(@registers[RSI], @size))
        @registers[RSI] += @size
        @registers[RDI] += @size
      end

      def store_string
        write_memory(@registers[RDI], read_register(RAX))
        @registers[RDI] += @size
      end

      # ---- two-byte opcodes -----------------------------------------------------

      def extended(opcode)
        case opcode
        when 0x110, 0x128 then load_wide
        when 0x111, 0x129 then store_wide
        when 0x11E, 0x11F then modrm
        when 0x140..0x14F then move_if(opcode)
        when 0x16E then move_into_wide
        when 0x17E then move_out_of_wide
        when 0x180..0x18F then branch_far(opcode)
        when 0x190..0x19F then set_byte(opcode)
        when 0x1AF then multiply_into_reg
        when 0x1B6, 0x1B7 then widen(opcode == 0x1B6 ? 1 : 2, false)
        when 0x1BE, 0x1BF then widen(opcode == 0x1BE ? 1 : 2, true)
        when 0x1D6 then store_quad
        when 0x1EF then exclusive_or_wide
        else unknown(opcode)
        end
      end

      # An instruction this file has never met. It is worth stopping over rather than
      # stepping past: either the compiler has started emitting something new, or the run
      # is reading data as though it were code, and both are answers.
      def unknown(opcode)
        raise format("instruction 0f %02x, at %x", opcode & 0xFF, @rip)
      end

      def move_if(opcode)
        modrm
        value = read_rm
        write_reg(value) if satisfied?(opcode & 0xF)
      end

      def branch_far(opcode)
        offset = fetch_signed32
        jump(offset) if satisfied?(opcode & 0xF)
      end

      def set_byte(opcode)
        modrm
        @size = 1
        write_rm(satisfied?(opcode & 0xF) ? 1 : 0)
      end

      def multiply_into_reg
        modrm
        write_reg(multiplied(read_reg, read_rm))
      end

      def widen(from, signed)
        modrm
        kept = @size
        @size = from
        value = read_rm
        @size = kept
        write_reg(signed ? extend_sign(value, from * 8) & MASK : value)
      end

      def load_wide
        modrm
        @wide[@reg] = read_wide
      end

      def store_wide
        modrm
        write_wide(@wide[@reg])
      end

      def read_wide
        return @wide[@rm] if @rm

        low, high = @memory.read(address, 16).unpack("Q<2")
        low | (high << 64)
      end

      def write_wide(value)
        return @wide[@rm] = value if @rm

        @memory.write(address, [value & MASK, value >> 64].pack("Q<2"))
      end

      def exclusive_or_wide
        modrm
        @wide[@reg] ^= read_wide
      end

      def move_into_wide
        @size = wide? ? 8 : 4
        modrm
        @wide[@reg] = read_rm
      end

      # The same opcode two ways: with the repeat prefix it fills a wide register from
      # memory, and without it, it empties one into a register or memory.
      def move_out_of_wide
        @size = wide? ? 8 : 4
        modrm
        return @wide[@reg] = @rm ? @wide[@rm] & MASK : @memory.read64(address) if @repeat == 0xF3

        write_rm(@wide[@reg] & masked(-1))
      end

      def store_quad
        modrm
        value = @wide[@reg] & MASK
        @rm ? @wide[@rm] = value : @memory.write64(address, value)
      end
    end
  end
end
