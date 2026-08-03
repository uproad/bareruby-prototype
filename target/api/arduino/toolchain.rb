# frozen_string_literal: true

require "fileutils"

require_relative "../toolchain"
require_relative "build"

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
    # arduino-cli installs itself wherever it is unpacked. This is where the README puts
    # it; one already on PATH wins, because a desk that has it has said so.
    INSTALL = "~/toolchains/arduino-cli"

    IMAGES = {
      "bareruby_program.ino.hex" => "bareruby_program.hex",
      "bareruby_program.ino.elf" => "bareruby_program.elf"
    }.freeze

    def self.run(directory, options: {})
      gather(directory)
      return false unless Toolchain.run(directory, Toolchain.recorded_command(directory), environment)

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

    def self.environment = { "PATH" => "#{ENV.fetch('PATH', '')}:#{File.expand_path(INSTALL)}" }

    def self.artifact(directory) = File.join(directory, IMAGES.values.first)
  end
end
