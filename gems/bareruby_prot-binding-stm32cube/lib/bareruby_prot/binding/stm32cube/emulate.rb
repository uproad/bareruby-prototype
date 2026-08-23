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

    def self.run(directory, into:, seconds:, options: {})
      command = renode
      return absent(command) unless File.executable?(command)

      board = Stm32CubeBinding::Manifests.board(Toolchain.recorded(directory, "board"))
      family = Stm32CubeBinding::FAMILIES.fetch(board.family)
      FileUtils.rm_rf(into)
      FileUtils.mkdir_p(into)
      File.write(File.join(into, "machine.repl"),
                 family.renode_platform(board, family.clock(board)))
      File.write(File.join(into, "run.resc"), script(board, directory, into, seconds))
      heard(command, into, board)
    end

    # Renode resolves a relative @path against its own installation directory, not
    # against where it was started — so every path handed to it is absolute.
    def self.script(board, directory, into, seconds)
      stdout = board.stdout_uart
      lines = ["mach create #{board.key.inspect}",
               "machine LoadPlatformDescription @#{File.join(into, 'machine.repl')}",
               "sysbus LoadELF @#{File.join(directory, Stm32CubeToolchain::ARTIFACT)}",
               format("sysbus.cpu VectorTableOffset 0x%X", board.device.flash.origin)]
      if stdout
        lines << "sysbus.#{stdout.instance.downcase} CreateFileBackend " \
                 "@#{File.join(into, 'uart.log')}"
      end
      lines << format('emulation RunFor "%d:%02d:%02d"',
                      seconds / 3600, (seconds % 3600) / 60, seconds % 60)
      lines << "quit"
      "#{lines.join("\n")}\n"
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

    def self.absent(at)
      warn "bareruby: the pinned Renode is not at #{at}"
      warn "          Install the pinned dependencies once:  #{Stm32CubeToolchain::INSTALL}"
      false
    end
  end
end
