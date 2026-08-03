# frozen_string_literal: true

require "json"

require_relative "../toolchain"
require_relative "toolchain"

module BareRubyProt
  # A board reached through this core is written to over the same serial port it talks
  # on, and the port is what identifies it — there is no image to read the chip out of and
  # no volume to copy onto.
  #
  # Which port, though, is not a guess worth making: several boards can be attached and
  # only some of them are this one. So arduino-cli is asked which ports carry the board
  # this firmware was built for, and a port is named in target.yml only when that answer
  # is more than one.
  module ArduinoFlash
    COMMAND = "arduino-cli"

    def self.run(directory, boards:, options: {})
      image = File.join(directory, "bareruby_program.hex")
      fqbn = Toolchain.recorded(directory, "fqbn")
      ports = boards.empty? ? found(fqbn) : boards.map(&:to_s)
      return false if ports.empty?

      ports.all? do |port|
        system(environment, COMMAND, "upload", "-p", port, "--fqbn", fqbn, "--input-file", image)
      end
    end

    # A board answers with the three parts of its name and not the fourth, so the chip the
    # build chose is left off the comparison.
    def self.found(fqbn)
      wanted = fqbn.split(":").first(3).join(":")
      ports = attached.select { |_, boards| boards.include?(wanted) }.keys
      return ports if ports.length == 1

      warn(if ports.empty?
             "flash: no attached board is #{wanted}."
           else
             "flash: #{ports.length} attached boards are #{wanted}, so nothing says " \
             "which one to write. Name a port in target.yml: #{ports.join(', ')}"
           end)
      []
    end

    def self.attached
      listing = IO.popen([environment, COMMAND, "board", "list", "--format", "json"], &:read)
      JSON.parse(listing).fetch("detected_ports", []).to_h do |detected|
        [detected.dig("port", "address"),
         (detected["matching_boards"] || []).map { |board| board["fqbn"] }]
      end
    end

    def self.environment = ArduinoToolchain.environment
  end
end
