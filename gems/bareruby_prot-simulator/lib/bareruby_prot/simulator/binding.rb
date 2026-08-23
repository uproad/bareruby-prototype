# frozen_string_literal: true

require_relative "clock"
require_relative "cpu"
require_relative "memory"
require_relative "program"

module BareRubyProt
  module Simulator
    # **The binding, written on this side of the call.** A binding is what a generated
    # call arrives at, spelled in the words of whatever answers it; on a board that is C
    # over an SDK, and here it is Ruby over an interpreter. The program is loaded and its
    # instructions are run, and the functions a binding implements are trapped at their
    # own addresses so that a call reaches a machine (`Machine`) instead of the stub the
    # artifact carries.
    #
    # Everything else runs as the instructions say — the language runtime, the C the
    # standard classes ship with, the program itself — which is why what a program
    # computes is the program's answer and not this side's.
    #
    # A name the artifact asked for and nobody defined is answered the same way, at an
    # address of this side's choosing: to the program, the C library is a trap too.
    class Binding
      STACK = 0x7000_0000
      THREAD = 0x6000_0000
      SCRATCH = 0x5000_0000
      TRAPS = 0x1000_0000
      SENTINEL = 0x0FFF_0000

      # Where the first six arguments of a call are, and where its answer goes.
      ARGUMENTS = [Cpu::RDI, Cpu::RSI, Cpu::RDX, Cpu::RCX, 8, 9].freeze

      attr_reader :memory, :cpu, :instructions

      def initialize(path, clock:)
        @program = Program.new(path)
        @clock = clock
        @memory = Memory.new
        @cpu = Cpu.new(@memory)
        @traps = {}
        @next_trap = TRAPS
        @scratch = SCRATCH
        @stopped = false
        @instructions = 0
        @program.load(@memory)
      end

      # What answers in Ruby: functions by name, and the few names that are a value
      # rather than a call. Both are given at once, because a relocation is read once and
      # cannot be read again for the other kind.
      def prepare(calls, values = {})
        @program.relocate(@memory) do |name|
          values[name] || (calls[name] && trap(calls[name]))
        end
        @program.defined.each do |address, name|
          @traps[address] = calls[name] if calls.key?(name)
        end
        @cpu.set_register(Cpu::RSP, STACK)
        @cpu.fs_base = THREAD
      end

      def stop = @stopped = true

      def stopped? = @stopped

      def run(name) = drive(address_of(name))

      # Where a name the artifact defined begins, for a trap that has to call back into
      # the program to answer.
      def address_of(name) = @program.address_of(name)

      def unwinding = @program.unwinding

      # A trap that does not go back where it was called from. Throwing is the one that
      # does this: what it lands on is a frame further up, and the return address the
      # call left is not where anything continues.
      def resume(address)
        @cpu.rip = address
        @returning = false
      end

      # Calling back into the program: an interrupt handler, or a runtime function a
      # peripheral needs to answer with. The sentinel return address is what says the
      # call is over, so a call from a trap nests inside the run that reached it.
      def drive(address, *arguments)
        arguments.each_with_index { |value, index| @cpu.set_register(ARGUMENTS[index], value) }
        entered = @cpu.rip
        @cpu.push(SENTINEL)
        @cpu.rip = address
        step until @cpu.rip == SENTINEL || @stopped || @cpu.halted? || @clock.over?
        @cpu.rip = entered
        @cpu.register(Cpu::RAX)
      end

      def argument(index)
        return @cpu.register(ARGUMENTS[index]) if index < ARGUMENTS.length

        @memory.read64(@cpu.register(Cpu::RSP) + ((index - ARGUMENTS.length + 1) * 8))
      end

      def signed_argument(index) = signed32(argument(index))

      def answer(value) = @cpu.set_register(Cpu::RAX, value)

      def string(pointer) = @memory.string(pointer)

      def bytes(pointer, length) = @memory.read(pointer, length)

      def signed32(value)
        value &= 0xFFFF_FFFF
        value >= 0x8000_0000 ? value - 0x1_0000_0000 : value
      end

      # Somewhere to put a string the program is going to be handed a pointer to. A run
      # writes a handful of them and never takes one back, so there is nothing to free.
      def place(bytes)
        where = @scratch
        @memory.write(where, "#{bytes}\0")
        @scratch += bytes.bytesize + 1
        where
      end

      private

      def step
        @instructions += 1
        @clock.advance(Clock::INSTRUCTION)
        handler = @traps[@cpu.rip]
        return @cpu.step unless handler

        @returning = true
        handler.call(self)
        @cpu.rip = @cpu.pop if @returning
      end

      def trap(handler)
        where = @next_trap
        @traps[where] = handler
        @next_trap += 16
        where
      end
    end
  end
end
