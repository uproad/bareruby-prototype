# frozen_string_literal: true

require "English"
require "fileutils"

require "bareruby_prot/toolchain"

require_relative "manifests"
require_relative "toolchain"
require_relative "family/stm32f4"

module BareRubyProt
  # The built firmware run with no board attached: Renode models the machine from the
  # same manifests the firmware was built from, headless, in virtual time. What comes
  # out is what the board's stdout UART said, which is the same thing the host build
  # says on fd1 — so one diff answers whether the firmware agrees with the host. Virtual
  # time makes that answer the same on every run and every desk, which is what lets CI
  # hold it.
  module Stm32CubeEmulate
    # LF-normalized, because the firmware's stdio ends lines CRLF and the host's ends
    # them LF, and the diff this file exists for is against the host.
    UART_CAPTURE = "uart.txt"

    def self.run(directory, into:, seconds:, input: nil, options: {})
      command = renode
      return absent(command) unless File.executable?(command)

      board = Stm32CubeBinding::Manifests.board(Toolchain.recorded(directory, "board"))
      return deaf(board, input) if input && board.stdout_uart.nil?

      family = Stm32CubeBinding::FAMILIES.fetch(board.family)
      FileUtils.rm_rf(into)
      FileUtils.mkdir_p(into)
      File.write(File.join(into, "machine.repl"),
                 family.renode_platform(board, family.clock(board)))
      File.write(File.join(into, "run.resc"),
                 script(board, family, directory, into, seconds, input))
      heard(command, into, board)
    end

    # Renode resolves a relative @path against its own installation directory, not
    # against where it was started — so every path handed to it is absolute.
    def self.script(board, family, directory, into, seconds, input)
      stdout = board.stdout_uart
      lines = ["mach create #{board.key.inspect}",
               "machine LoadPlatformDescription @#{File.join(into, 'machine.repl')}",
               "sysbus LoadELF @#{File.join(directory, Stm32CubeToolchain::ARTIFACT)}",
               format("sysbus.cpu VectorTableOffset 0x%X", board.device.flash.origin)]
      if stdout
        lines << "sysbus.#{stdout.instance.downcase} CreateFileBackend " \
                 "@#{File.join(into, 'uart.log')}"
        lines.concat(fed(family, stdout, input)) if input
      end
      lines << format('emulation RunFor "%d:%02d:%02d"',
                      seconds / 3600, (seconds % 3600) / 60, seconds % 60)
      lines << "quit"
      "#{lines.join("\n")}\n"
    end

    # The file's bytes, queued into the UART model before the machine runs a cycle —
    # which is the host's condition exactly: a program whose stdin is a pipe finds every
    # byte already waiting. Two accommodations make that true. The receiver is switched
    # on first, because the model drops what arrives while it is off, and no instruction
    # has run yet to turn it on. And the queue leads with one NUL, because the firmware
    # flushes the data register when it arms the receive side — on hardware that is
    # power-on garbage, here it would be the first real byte — so the flush is given a
    # byte that stands for the garbage. One WriteChar per byte; nothing is appended.
    def self.fed(family, stdout, input)
      register, value = family.uart_receiver_on(stdout.instance)
      wire = stdout.instance.downcase
      [format("sysbus WriteDoubleWord 0x%X 0x%X", register, value)] +
        "\x00#{File.binread(input)}".each_byte.map do |byte|
          format("sysbus.#{wire} WriteChar 0x%02X", byte)
        end
    end

    # Renode's own account of the run goes to a file and is said only when the run
    # refused, exactly as toolchain output is. What is said on success is the UART's.
    def self.heard(command, into, board)
      output = IO.popen([command, "--disable-xwt", "--console", "--plain",
                         "-e", "include @#{File.join(into, 'run.resc')}"],
                        err: %i[child out], &:read)
      File.write(File.join(into, "renode.log"), output)
      raw = File.join(into, "uart.log")
      unless $CHILD_STATUS.success? && (board.stdout_uart.nil? || File.exist?(raw))
        warn output
        return false
      end

      said = File.exist?(raw) ? File.read(raw).gsub("\r\n", "\n") : ""
      kept = File.join(into, UART_CAPTURE)
      File.write(kept, said)
      said.each_line { |line| warn line.chomp }
      warn "emulate: #{kept.delete_prefix("#{Dir.pwd}/")} holds that, ready for a diff."
      true
    end

    # The pinned Renode from the lock, unless the desk names its own.
    def self.renode
      return ENV["RENODE"] if ENV["RENODE"]

      File.join(Stm32CubeToolchain::TOOLS,
                Stm32CubeToolchain::LOCK.dig("emulate", "renode", "directory"), "renode")
    end

    # Input rides the stdout UART's RX — the same wire, both directions, exactly as the
    # host's stdin and stdout are one terminal. A board without that wire has nowhere to
    # be fed.
    def self.deaf(board, input)
      warn "bareruby: #{board.key} names no stdout UART, so #{input} has nowhere to arrive."
      false
    end

    def self.absent(at)
      warn "bareruby: the pinned Renode is not at #{at}"
      warn "          Install the pinned dependencies once:  #{Stm32CubeToolchain::INSTALL}"
      false
    end
  end
end
