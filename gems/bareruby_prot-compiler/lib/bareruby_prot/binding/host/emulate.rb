# frozen_string_literal: true

require "fileutils"
require "stringio"

module BareRubyProt
  # The host build run with no board attached. The machine doing the compiling is the one
  # machine whose build already runs here, so what this adds is not a way to run it — it
  # is a board to run it against: the peripheral calls that would have printed what they
  # were asked land on objects that remember, and the program's own output comes back
  # unchanged.
  #
  # What the program said goes on screen and into a file, the way the emulated boards
  # leave theirs, so the same `diff` answers whether they agree. What the serial ports
  # sent is kept beside it, because on this board that is a different thing from what the
  # program printed: there is no wire, and the port kept every byte instead.
  #
  # **The simulator is a gem rather than a program, and is looked for the same way.** A
  # desk without it has a target that builds and does not emulate, which is an answer.
  module HostEmulate
    ARTIFACT = "bareruby_program"

    SAID = "stdout.txt"

    SENT = "uart.txt"

    def self.run(directory, into:, seconds:, input: nil, options: {})
      return absent unless simulator?

      FileUtils.rm_rf(into)
      FileUtils.mkdir_p(into)
      said = StringIO.new(+"".b, "wb")
      receiving(input) do |wire|
        run = Simulator.run(File.join(directory, ARTIFACT), seconds: seconds, out: said,
                                                            input: wire)
        heard(into, said.string, run.board)
      end
    end

    # What the ports receive on. A file named on the command line is the same wire an
    # emulated board is fed through, so the two runs read the same bytes; with nothing
    # named it is this terminal's own input, which is what the native build reads.
    def self.receiving(input)
      return yield($stdin) unless input

      File.open(input, "rb") { |file| yield(file) }
    end

    # Two things were said and they are not the same thing, so they are labelled. What
    # the program printed is what the host build prints and what an emulated board's
    # stdout UART says, which is the diff this file exists for; what a port sent is what
    # this board kept instead of putting it on a wire.
    def self.heard(into, said, board)
      sent = sent(board)
      File.write(File.join(into, SAID), said)
      File.write(File.join(into, SENT), sent)
      said.each_line { |line| warn line.chomp }
      sent.each_line { |line| warn "uart: #{line.chomp}" }
      warn "emulate: #{shown(File.join(into, SAID))} holds that, ready for a diff."
      true
    end

    # Every port's send side, in unit order. Nothing on this board reads them, so what a
    # program wrote is all still there.
    def self.sent(board) = board.uart.values.map(&:transmitted).join

    def self.shown(path) = path.delete_prefix("#{Dir.pwd}/")

    def self.simulator?
      require "bareruby_prot/simulator"
      true
    rescue LoadError
      false
    end

    def self.absent
      warn "bareruby: the simulator gem is not in this project's bundle"
      warn '          Add it once:  gem "bareruby_prot-simulator"'
      false
    end
  end
end
