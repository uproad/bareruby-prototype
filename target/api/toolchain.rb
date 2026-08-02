# frozen_string_literal: true

require "English"

module BareRubyProt
  # What every API's second stage has in common. The build already wrote down what it is —
  # manifest.txt carries the command that turns the generated C++ into an artifact — so
  # running it is reading that line back rather than keeping a second copy of it here.
  # A toolchain that a manifest cannot describe in one line says so by not using this.
  module Toolchain
    MANIFEST = "manifest.txt"

    def self.recorded_command(directory)
      File.read(File.join(directory, MANIFEST))[/^build_command = (.+)$/, 1]
    end

    # A toolchain is chatty even when everything is fine, so its output is kept for the
    # failure it explains and said nothing about otherwise.
    #
    # A failure here is another program's, and that program has already said what went
    # wrong. Answering false rather than raising is what keeps this side from burying that
    # explanation under a stack of its own.
    def self.run(directory, command, environment = {})
      output = nil
      status = nil
      Dir.chdir(directory) do
        IO.popen(environment, ["sh", "-c", command], err: %i[child out]) { |io| output = io.read }
        status = $CHILD_STATUS
      end
      return true if status.success?

      warn output
      warn "bareruby: the second stage failed in #{directory}"
      false
    end
  end
end
