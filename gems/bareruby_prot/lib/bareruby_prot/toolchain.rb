# frozen_string_literal: true

require "English"

module BareRubyProt
  # How this side runs somebody else's program: a second stage, a flashing script, a fetch.
  # What they have in common is that their output is this side's to place — never straight
  # to the terminal, which belongs to whatever is being drawn there.
  #
  # What every binding's second stage has in common. The build already wrote down what it is —
  # manifest.txt carries the command that turns the generated C++ into an artifact — so
  # running it is reading that line back rather than keeping a second copy of it here.
  # A toolchain that a manifest cannot describe in one line says so by not using this.
  module Toolchain
    MANIFEST = "manifest.txt"

    # The manifest is what the build wrote down about itself, so anything a later step
    # needs to know about the build is read back from it rather than worked out again.
    # Flashing reaches for it too, which is what lets it need nothing but the directory.
    def self.recorded(directory, name)
      File.read(File.join(directory, MANIFEST))[/^#{name} = (.+)$/, 1]
    end

    def self.recorded_command(directory) = recorded(directory, "build_command")

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

    # The other way to run somebody else's program: aloud, for what it says rather than
    # only for what it leaves behind. A script that writes a chip names the board it found
    # and the volume it wrote, which is the only account of what reached the hardware, and
    # a fetch narrates a download nobody else can see.
    #
    # **Said through warn rather than to the terminal**, because a run is drawing a table
    # there and everything else speaks above it. Where there is no table, warn is where all
    # of this went anyway.
    def self.aloud(command, environment = {})
      warn IO.popen(environment, command, err: %i[child out], &:read)
      $CHILD_STATUS.success?
    end
  end
end
