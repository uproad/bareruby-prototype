# frozen_string_literal: true

require "yaml"

require "bareruby_prot/toolchain"

module BareRubyProt
  # OpenOCD over the ST-LINK: write, verify, reset. The probe and the target script are
  # the build manifest's answer — recorded when the firmware was made, so flashing needs
  # nothing but the directory. An ST-LINK reaches the chip over SWD rather than
  # presenting a volume, so what identifies a board here is the probe's serial; with one
  # probe attached there is nothing to say.
  module Stm32CubeFlash
    def self.run(directory, boards:, options: {}, found: nil)
      image = File.join(directory, "bareruby_program.elf")
      interface = Toolchain.recorded(directory, "openocd_interface")
      target = Toolchain.recorded(directory, "openocd_target")
      serials = boards.empty? ? [nil] : boards
      serials.all? do |serial|
        Toolchain.aloud([openocd, *(serial ? ["-c", "adapter serial #{serial}"] : []),
                         "-f", "interface/#{interface}.cfg",
                         "-f", "target/#{target}.cfg",
                         "-c", "program #{image} verify reset exit"])
      end
    end

    # The pinned xPack OpenOCD from the lock, unless the desk names its own.
    def self.openocd
      return ENV["OPENOCD"] if ENV["OPENOCD"]

      File.join(Stm32CubeToolchain::TOOLS,
                Stm32CubeToolchain::LOCK.dig("common", "openocd", "directory"),
                "bin", "openocd")
    end
  end
end
