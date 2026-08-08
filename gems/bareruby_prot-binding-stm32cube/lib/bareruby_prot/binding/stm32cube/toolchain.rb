# frozen_string_literal: true

require "yaml"

require "bareruby_prot/toolchain"

module BareRubyProt
  # make, over what the first stage generated, against the pinned GCC and the pinned
  # STM32Cube checkout. Both live under the desk's .tools/ at the paths the lock file
  # names — found from where the command was run, because an SDK belongs to the desk
  # rather than to the gem that asks for it. A desk that keeps its own toolchain
  # elsewhere says so in the environment, and the lock still names the SDK.
  module Stm32CubeToolchain
    TOOLS = File.expand_path(".tools", Dir.pwd)
    LOCK = YAML.safe_load_file(File.expand_path("data/sources.lock.yml", __dir__)).freeze
    INSTALL = File.expand_path("install.sh", __dir__)
    ARTIFACT = "bareruby_program.elf"

    def self.run(directory, options: {})
      family = Toolchain.recorded(directory, "family")
      cube = File.join(TOOLS, LOCK.dig("families", family, "cube", "directory"))
      return absent("the pinned #{family} SDK", cube) unless File.directory?(cube)
      return absent("the pinned ARM toolchain", "#{prefix}-g++") unless File.executable?("#{prefix}-g++")

      Toolchain.as_recorded(directory, { "TOOLCHAIN" => prefix, "CUBE" => cube })
    end

    def self.prefix
      home = ENV["ARM_TOOLCHAIN_PATH"] ||
             File.join(TOOLS, LOCK.dig("common", "arm_gcc", "directory"))
      File.join(home, "bin", "arm-none-eabi")
    end

    # A build never downloads. What is missing is named, with the one command that
    # provides it, and the run stops — which is what keeps local and CI inputs the same.
    def self.absent(what, at)
      warn "bareruby: #{what} is not at #{at}"
      warn "          Install the pinned dependencies once:  #{INSTALL}"
      false
    end

    def self.artifact(directory) = File.join(directory, ARTIFACT)
  end
end
