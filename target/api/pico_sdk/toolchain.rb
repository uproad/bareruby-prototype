# frozen_string_literal: true

require "fileutils"

require_relative "../toolchain"

module BareRubyProt
  # cmake and pico-sdk, which the manifest spells out, plus the three paths the SDK has to
  # be told before it will run at all. cmake leaves its own tree behind and the firmware
  # inside it, so the images come up one level to sit beside the sources they were made
  # from — what a board is given should not be found by knowing how cmake arranges itself.
  module PicoSdkToolchain
    # One SDK serves every board: RP2350 needs 2.0.0 or newer, and RP2040 is still
    # supported there, so there is no reason to keep a second checkout for it.
    PATHS = {
      "PICO_SDK_PATH" => "~/pico/pico-sdk-2",
      "PICO_TOOLCHAIN_PATH" => "~/toolchains/arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi",
      # SDK 2.x builds picotool on demand. Left alone it lands inside the target's build
      # tree, which the next first-stage run deletes, so it is kept outside of it instead.
      "PICOTOOL_FETCH_FROM_GIT_PATH" => "~/pico/picotool"
    }.freeze

    IMAGES = ["bareruby_program.uf2", "bareruby_program.elf"].freeze

    def self.run(directory, options: {})
      Toolchain.run(directory, Toolchain.recorded_command(directory), environment)
      IMAGES.each do |image|
        made = File.join(directory, "build", image)
        FileUtils.cp(made, File.join(directory, image)) if File.exist?(made)
      end
    end

    def self.environment
      PATHS.to_h { |name, default| [name, ENV[name] || File.expand_path(default)] }
    end

    def self.artifact(directory) = File.join(directory, IMAGES.first)
  end
end
