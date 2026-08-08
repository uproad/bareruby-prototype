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
  # A binding whose second stage a manifest describes in full says so by declaring no
  # toolchain at all, and what is here answers for it.
  module Toolchain
    MANIFEST = "manifest.txt"

    # The manifest is what the build wrote down about itself, so anything a later step
    # needs to know about the build is read back from it rather than worked out again.
    # Flashing reaches for it too, which is what lets it need nothing but the directory.
    def self.recorded(directory, name)
      File.read(File.join(directory, MANIFEST))[/^#{name} = (.+)$/, 1]
    end

    def self.recorded_command(directory) = recorded(directory, "build_command")

    # **This is the second stage a binding gets without asking for one.** The manifest
    # names what to run and what that run leaves behind, and reading those two lines back
    # needs to know nothing about any machine — so a binding whose second stage is spelled
    # out there declares no toolchain, and this answers in its place.
    def self.run(directory, options: {}) = as_recorded(directory)

    def self.artifact(directory) = File.join(directory, recorded(directory, "artifact"))

    # A toolchain is chatty even when everything is fine, so its output is kept for the
    # failure it explains and said nothing about otherwise.
    #
    # A failure here is another program's, and that program has already said what went
    # wrong. Answering false rather than raising is what keeps this side from burying that
    # explanation under a stack of its own.
    #
    # What a binding adds is around this rather than instead of it: paths an SDK has to be
    # told before it will run, and the images it leaves somewhere of its own choosing.
    def self.as_recorded(directory, environment = {})
      command = recorded_command(directory)
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
