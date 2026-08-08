# frozen_string_literal: true

require "fileutils"

require "bareruby_prot/toolchain"

require_relative "build"
require_relative "tools"

module BareRubyProt
  # arduino-cli reads a sketch, and a sketch is a directory rather than a file list. So
  # the declaration the first stage makes — these are the translation units this program
  # reached for — is met by gathering exactly those into one directory and handing it over.
  # Headers go in whole, because every program uses them; a source goes in only if the
  # program reached it, which is what keeps the link boundary a build system this side
  # does not own cannot see.
  #
  # What comes back is left where cmake's is: beside the sources it was made from, under a
  # name that does not carry how the tool arranges itself.
  module ArduinoToolchain
    IMAGES = {
      "bareruby_program.ino.hex" => "bareruby_program.hex",
      "bareruby_program.ino.elf" => "bareruby_program.elf"
    }.freeze

    def self.run(directory, options: {})
      gather(directory)
      return false unless Toolchain.as_recorded(directory, environment)

      IMAGES.each do |made, kept|
        path = File.join(directory, made)
        FileUtils.mv(path, File.join(directory, kept)) if File.exist?(path)
      end
      true
    end

    def self.gather(directory)
      sketch = File.join(directory, ArduinoBuild::SKETCH)
      sources = Toolchain.recorded(directory, "sources").split.map do |source|
        File.expand_path(source, directory)
      end
      (sources + Dir[File.join(directory, "..", "*.h")]).each do |path|
        FileUtils.cp(path, File.join(sketch, File.basename(path)))
      end
    end

    # **What this binding is built with belongs to the desk, not to a project and not to
    # this gem.** One core serves every project on a machine, and it is 325 MB of somebody
    # else's compiler — a binding that reached out of its own directory for one would be
    # looking inside itself, and one that filed it under whichever project built first
    # would make the next project fetch it again. Where the store is is the ecosystem's
    # answer; which things go in it is this binding's, and it is written down in the lock
    # beside tools.rb.
    #
    # The command is looked for on PATH before the store's copy, because a desk that has
    # its own has said so — and the fetching side reads that same answer, so the copy this
    # falls back to is one that was only ever downloaded when it was going to be used.
    def self.environment
      ArduinoTools.environment
                  .merge("PATH" => "#{ENV.fetch('PATH', '')}:#{ArduinoTools.command_directory}")
    end

    def self.artifact(directory) = File.join(directory, IMAGES.values.first)
  end
end
