# frozen_string_literal: true

require "fileutils"

require_relative "../toolchain"

module BareRubyProt
  # cmake and pico-sdk, which the manifest spells out, plus the three paths the SDK has to
  # be told before it will run at all. cmake leaves its own tree behind and the firmware
  # inside it, so the images come up one level to sit beside the sources they were made
  # from — what a board is given should not be found by knowing how cmake arranges itself.
  module PicoSdkToolchain
    # What this API is built with lives under the repository, one directory per API, and
    # each of them says which version it is. A version is not a detail here: moving from
    # 1.5.1 to 2.3.0 changed every size this repository has recorded, so a figure without
    # the version it was measured under says less than it appears to. A desk that keeps
    # its own copies elsewhere says so through the environment, which still wins.
    TOOLS = File.expand_path("../../../.tools", __dir__)

    # One SDK serves every board: RP2350 needs 2.0.0 or newer, and RP2040 is still
    # supported there, so there is no reason to keep a second checkout for it.
    #
    # The ARM toolchain is filed under common/ rather than here, because the STM32 boards
    # are built by the same compiler — a thing two APIs reach for is not either one's.
    # What it is common to is an instruction set, so that is the shelf it sits on.
    PATHS = {
      "PICO_SDK_PATH" => "pico_sdk/pico-sdk-2.3.0",
      "PICO_TOOLCHAIN_PATH" => "common/arm/arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi",
      # SDK 2.x builds picotool on demand. Left alone it lands inside the target's build
      # tree, which the next first-stage run deletes, so it is kept outside of it instead.
      # Which picotool that is, is the SDK's decision, so it carries the SDK's version.
      "PICOTOOL_FETCH_FROM_GIT_PATH" => "pico_sdk/picotool-2.3.0"
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
      PATHS.to_h { |name, default| [name, ENV[name] || File.join(TOOLS, default)] }
    end

    def self.artifact(directory) = File.join(directory, IMAGES.first)
  end
end
