# frozen_string_literal: true

require "fileutils"

require "bareruby_prot/toolchain"
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
    TOOLS = File.expand_path("../../../.tools/arduino", __dir__)

    # arduino-cli installs itself wherever it is unpacked, so it is unpacked under the
    # repository, beside the version it is — a core's output is the version of the tool
    # that produced it. One already on PATH wins, because a desk that has it has said so.
    INSTALL = File.join(TOOLS, "arduino-cli-1.5.2-rc.1")

    # The core is the compiler: avr-gcc, avr-libc and avrdude arrive with it, and they are
    # what actually builds a sketch. Left alone arduino-cli files them under ~/.arduino15,
    # which would leave the largest part of this binding's toolchain outside the repository
    # while the command that drives it sits inside. These say otherwise. Versions are not
    # in the names because arduino-cli keeps its own inside — one directory holds every
    # core and every tool version it has been asked for.
    DIRECTORIES = {
      "ARDUINO_DIRECTORIES_DATA" => "data",
      "ARDUINO_DIRECTORIES_DOWNLOADS" => "downloads",
      "ARDUINO_DIRECTORIES_USER" => "user"
    }.freeze

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

    def self.environment
      directories = DIRECTORIES.to_h { |name, place| [name, ENV[name] || File.join(TOOLS, place)] }
      directories.merge("PATH" => "#{ENV.fetch('PATH', '')}:#{INSTALL}")
    end

    def self.artifact(directory) = File.join(directory, IMAGES.values.first)
  end
end
