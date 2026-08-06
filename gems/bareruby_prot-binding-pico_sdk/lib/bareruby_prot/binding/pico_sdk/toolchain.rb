# frozen_string_literal: true

require "fileutils"

require "bareruby_prot/toolchain"

require_relative "tools"

module BareRubyProt
  # cmake and pico-sdk, which the manifest spells out, plus the three paths the SDK has to
  # be told before it will run at all. cmake leaves its own tree behind and the firmware
  # inside it, so the images come up one level to sit beside the sources they were made
  # from — what a board is given should not be found by knowing how cmake arranges itself.
  module PicoSdkToolchain
    # **What this binding is built with belongs to the desk, not to a project and not to
    # this gem.** One pico-sdk serves every project on a machine; an SDK is a gigabyte of
    # somebody else's release, so a binding that reached out of its own directory for one
    # would be looking inside itself. Where the store is, and how the two shapes these come
    # in are fetched, is the ecosystem's answer; which of them are needed is this
    # binding's, and it is written down in the lock beside tools.rb.
    #
    # A desk that keeps its own copies elsewhere says so through the environment, which
    # still wins — and then nothing is fetched at all.
    #
    # One SDK serves every board: RP2350 needs 2.0.0 or newer, and RP2040 is still
    # supported there, so there is no reason to keep a second checkout for it.
    #
    # The ARM toolchain is filed under common/ rather than here, because the STM32 boards
    # are built by the same compiler — a thing two bindings reach for is not either one's.
    # What it is common to is an instruction set, so that is the shelf it sits on.
    IMAGES = ["bareruby_program.uf2", "bareruby_program.elf"].freeze

    def self.run(directory, options: {})
      Toolchain.run(directory, Toolchain.recorded_command(directory), environment)
      IMAGES.each do |image|
        made = File.join(directory, "build", image)
        FileUtils.cp(made, File.join(directory, image)) if File.exist?(made)
      end
    end

    def self.environment
      PicoSdkTools.paths.to_h { |name, held| [name, ENV[name] || Tools.at(held)] }
    end

    def self.artifact(directory) = File.join(directory, IMAGES.first)
  end
end
