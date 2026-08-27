# frozen_string_literal: true

require "English"
require "fileutils"

require "bareruby_prot/toolchain"

require_relative "tools"

module BareRubyProt
  # cmake and ESP-IDF, which the manifest spells out, plus the paths the SDK has to be
  # told before it will run at all — and one step of its own afterwards.
  #
  # **A board takes three images, and what leaves here is one.** ESP-IDF writes a
  # bootloader, a partition table and the program, each to its own offset in flash, and
  # `build/flash_args` beside them says which offset each goes to. Everything downstream of
  # a build here — what `build/` keeps, what flashing is handed — is one artifact, so the
  # three are merged into the single image those offsets describe, and writing a board is
  # one file at offset zero. The offsets stay the build's answer rather than becoming a
  # number this side or the flashing side carries.
  module EspIdfToolchain
    IMAGE = "bareruby_program.bin"

    ELF = "bareruby_program.elf"

    # What the second stage answered is what this answers. Merging the images and bringing
    # the ELF up is what happens after a build that worked, not the answer to whether it
    # did — and a run that reads the wrong one of those calls a failed build a success.
    def self.run(directory, options: {})
      return false unless Toolchain.as_recorded(directory, environment)

      made = File.join(directory, "build", ELF)
      FileUtils.cp(made, File.join(directory, ELF)) if File.exist?(made)
      merged(directory)
    end

    # esptool reads what the build wrote down about its own layout, so the offsets are
    # named once, by the side that decided them.
    def self.merged(directory)
      output = IO.popen(environment,
                        [EspIdfTools.command("esptool.py"), "--chip", Toolchain.recorded(directory, "chip"),
                         "merge_bin", "-o", File.join("..", IMAGE), "@flash_args"],
                        chdir: File.join(directory, "build"), err: %i[child out], &:read)
      return true if $CHILD_STATUS.success?

      warn output
      warn "bareruby: merging the images failed in #{directory}"
      false
    end

    # **What this binding is built with belongs to the desk, not to a project and not to
    # this gem.** One ESP-IDF serves every project on a machine, and it is two gigabytes of
    # somebody else's SDK and compiler — a binding that reached out of its own directory
    # for one would be looking inside itself. Where the store is is the ecosystem's answer;
    # which things go in it is this binding's, and it is written down in the lock beside
    # tools.rb.
    #
    # A desk that keeps its own copies elsewhere says so through `IDF_PATH` and
    # `IDF_TOOLS_PATH`, which still win — and then nothing was fetched at all.
    def self.environment = EspIdfTools.environment

    def self.artifact(directory) = File.join(directory, IMAGE)
  end
end
