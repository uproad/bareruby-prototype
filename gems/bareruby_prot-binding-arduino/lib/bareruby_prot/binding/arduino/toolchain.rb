# frozen_string_literal: true

require "English"
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

    # Where a build that takes more than one image writes down which offset each goes to.
    # The name is the core's, not this side's.
    LAYOUT = "flash_args"

    def self.run(directory, options: {})
      gather(directory)
      return false unless Toolchain.as_recorded(directory, environment)

      IMAGES.each do |made, kept|
        path = File.join(directory, made)
        FileUtils.mv(path, File.join(directory, kept)) if File.exist?(path)
      end
      merged(directory)
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

    # **A board that takes four images gets the one they describe.** An ESP32 is written a
    # bootloader, a partition table, an OTA selector and the program, each at its own
    # offset — and the build says which offset each goes to, in a file of its own beside
    # them. Everything downstream of a build here is one artifact, so the four are merged
    # into the single image those offsets describe and writing a board is one file at
    # offset zero. **The offsets stay the core's answer**: they are read out of what it
    # wrote rather than copied onto this side.
    #
    # A board that takes one image leaves no such file, and there is nothing here to do
    # for it.
    def self.merged(directory)
      build = File.join(directory, "build")
      return true unless File.exist?(File.join(build, LAYOUT))

      output = IO.popen(environment,
                        [ArduinoTools.writer(Toolchain.recorded(directory, "fqbn")),
                         "--chip", Toolchain.recorded(directory, "chip"), "merge-bin",
                         "-o", File.join("..", Toolchain.recorded(directory, "artifact")),
                         "@#{LAYOUT}"],
                        chdir: build, err: %i[child out], &:read)
      return true if $CHILD_STATUS.success?

      warn output
      warn "bareruby: merging the images failed in #{directory}"
      false
    end

    # **What this binding is built with belongs to the desk, not to a project and not to
    # this gem.** One core serves every project on a machine, and it is gigabytes of
    # somebody else's compiler — a binding that reached out of its own directory for one
    # would be looking inside itself, and one that filed it under whichever project built
    # first would make the next project fetch it again. Where the store is is the
    # ecosystem's answer; which things go in it is this binding's, and it is written down
    # in the lock beside tools.rb.
    #
    # The command is looked for on PATH before the store's copy, because a desk that has
    # its own has said so — and the fetching side reads that same answer, so the copy this
    # falls back to is one that was only ever downloaded when it was going to be used.
    def self.environment
      ArduinoTools.environment
                  .merge("PATH" => "#{ENV.fetch('PATH', '')}:#{ArduinoTools.command_directory}")
    end

    def self.artifact(directory) = Toolchain.artifact(directory)
  end
end
