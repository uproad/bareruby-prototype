# frozen_string_literal: true

module BareRubyProt
  # An ST-LINK reaches the chip over SWD rather than presenting a volume to copy onto, so
  # what identifies a board here is the probe's serial rather than the board's own. With
  # one probe attached there is nothing to say.
  #
  # This path has never been run: it is written from what STM32CubeProgrammer documents,
  # and the CubeIDE builds that produced the firmware it writes were flashed by hand.
  module Stm32CubeFlash
    PROGRAMMER = "STM32_Programmer_CLI"
    HOME_INSTALL = "~/STMicroelectronics/STM32Cube/STM32CubeProgrammer/bin/STM32_Programmer_CLI"

    def self.run(directory, boards:, options: {})
      image = File.join(directory, "bareruby_program.elf")
      ports = boards.empty? ? ["port=SWD"] : boards.map { |board| "port=SWD sn=#{board}" }
      ports.all? { |port| system(programmer, "-c", port, "-w", image, "-rst") }
    end

    def self.programmer
      return ENV["STM32_PROGRAMMER_CLI"] if ENV["STM32_PROGRAMMER_CLI"]

      home = File.expand_path(HOME_INSTALL)
      File.executable?(home) ? home : PROGRAMMER
    end
  end
end
