# frozen_string_literal: true

require "json"

require "bareruby_prot/toolchain"
require_relative "tools"

module BareRubyProt
  # A board reached through this core is written to over the same serial port it talks
  # on, and the port is what identifies it — there is no image to read the chip out of and
  # no volume to copy onto.
  #
  # Which port, though, is not a guess worth making: several boards can be attached and
  # only some of them are this one. So arduino-cli is asked which ports carry the board
  # this firmware was built for, and a port is named in target.yml only when that answer
  # is more than one.
  #
  # **Both runs here name the command by its path rather than by its word.** A second stage
  # is a line handed to a shell, and a shell looks a bare word up on the PATH it was given
  # — which is why the manifest can record `arduino-cli compile …` and stay readable on any
  # desk. Nothing runs a shell here: an argv is executed directly, and the resolving is
  # ruby's, against the PATH of this process rather than the one being passed in. A store
  # this side downloaded into is on neither. So the answer is asked of the side that knows
  # where the command ended up, which already answers it for the fetch.
  module ArduinoFlash
    def self.run(directory, boards:, options: {}, found: nil)
      image = File.join(directory, "bareruby_program.hex")
      fqbn = Toolchain.recorded(directory, "fqbn")
      ports = boards.empty? ? found(fqbn) : boards.map(&:to_s)
      return false if ports.empty?

      ports.all? do |port|
        Toolchain.aloud([ArduinoTools.command, "upload", "-p", port, "--fqbn", fqbn,
                         "--input-file", image], environment)
      end
    end

    # A board answers with the three parts of its name and not the fourth, so the chip the
    # build chose is left off the comparison.
    #
    # **Asked until the bus is done moving, rather than once.** A board is identified here
    # by the serial port it brought up, and the ports are renumbered whenever anything on
    # the bus arrives or leaves — which is exactly what a board being written elsewhere
    # does, twice, as it reboots into its bootloader and back. Asked once at the wrong
    # moment the answer is that this board is not attached, which is a different thing
    # from what is true. Every other place a run waits on hardware here waits the same
    # way.
    ATTEMPTS = 20
    PAUSE = 0.5

    def self.found(fqbn)
      wanted = fqbn.split(":").first(3).join(":")
      ports = []
      ATTEMPTS.times do
        ports = attached.select { |_, boards| boards.include?(wanted) }.keys
        break unless ports.empty?

        sleep PAUSE
      end
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
      listing = IO.popen([environment, ArduinoTools.command, "board", "list",
                          "--format", "json"], &:read)
      JSON.parse(listing).fetch("detected_ports", []).to_h do |detected|
        [detected.dig("port", "address"),
         (detected["matching_boards"] || []).map { |board| board["fqbn"] }]
      end
    end

    # The store's directories, and not the PATH the second stage is also given: with the
    # command named by its path there is nothing left here for a PATH to answer.
    def self.environment = ArduinoTools.environment
  end
end
