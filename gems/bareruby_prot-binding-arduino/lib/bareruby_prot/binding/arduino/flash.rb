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
    # **Not every board this core reaches is written by `arduino-cli upload`.** An ESP32
    # takes the image the same command would give it, at the same offsets, and then comes
    # back still waiting to be written: the only reset that can be driven over the chip's
    # own USB is the peripheral's own, and the chip reads that as another request to be
    # flashed. The upload recipe asks for a hard reset and there is no way to say otherwise
    # through it, so a board whose core names its own writer is written with that writer,
    # one merged image at offset zero, and reset from underneath the peripheral.
    def self.run(directory, boards:, options: {}, found: nil)
      fqbn = Toolchain.recorded(directory, "fqbn")
      writer = ArduinoTools.writer(fqbn)
      ports = boards.empty? ? found(fqbn, writer) : boards.map(&:to_s)
      return false if ports.empty?

      ports.all? do |port|
        writer ? written(directory, writer, port) : uploaded(directory, fqbn, port)
      end
    end

    def self.uploaded(directory, fqbn, port)
      Toolchain.aloud([ArduinoTools.command, "upload", "-p", port, "--fqbn", fqbn,
                       "--input-file", File.join(directory, Toolchain.recorded(directory, "artifact"))],
                      environment)
    end

    # Fast enough that writing is shorter than finding the port, and the speed the core's
    # own board list offers first.
    BAUD = "921600"

    # **What the build decided, kept.** The image carries its own flash mode, frequency and
    # size in its header, because the merge put them there out of what the core wrote down —
    # so `keep` is the whole of what this side has to say about all three.
    def self.written(directory, writer, port)
      Toolchain.aloud([writer, "--chip", Toolchain.recorded(directory, "chip"),
                       "--port", port, "--baud", BAUD,
                       "--before", "default-reset", "--after", after(port), "write-flash",
                       "--flash-mode", "keep", "--flash-freq", "keep", "--flash-size", "keep",
                       "0x0", File.join(directory, Toolchain.recorded(directory, "artifact"))],
                      environment)
    end

    # **The chip's own USB**, which a board wired for it brings up with no bridge chip in
    # between. That is what makes it the port that can always be written, and the one that
    # has to be reset differently afterwards: the RTC watchdog is a reset from underneath
    # the peripheral, and the board boots what it was just given. A bridge chip holds the
    # reset pin itself and takes the ordinary one.
    OWN_USB = "0x303A"

    def self.after(port)
      vendors[File.realpath(port)] == OWN_USB ? "watchdog-reset" : "hard-reset"
    end

    # A board answers with the three parts of its name and not the fourth, so the chip the
    # build chose is left off the comparison.
    #
    # **How much of a name a board answers with is the core's.** An AVR board carries a USB
    # id of its own and is recognised as itself, three words deep. Every board of the ESP32
    # family brings up one and the same USB device, so what a port answers there is the
    # family — and which board of it this is, the third word, is not something the bus can
    # say. The two go with the two ways a board of each is written, which is why the one
    # question answers both.
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

    def self.found(fqbn, writer)
      wanted = fqbn.split(":").first(writer ? 2 : 3).join(":")
      ports = []
      ATTEMPTS.times do
        ports = attached.select { |_, boards| boards.any? { |board| board.start_with?(wanted) } }.keys
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
      detected.to_h do |port|
        [port.dig("port", "address"),
         (port["matching_boards"] || []).map { |board| board["fqbn"] }]
      end
    end

    def self.vendors
      detected.to_h { |port| [port.dig("port", "address"), port.dig("port", "properties", "vid")] }
    end

    def self.detected
      listing = IO.popen([environment, ArduinoTools.command, "board", "list",
                          "--format", "json"], &:read)
      JSON.parse(listing).fetch("detected_ports", [])
    end

    # The store's directories, and not the PATH the second stage is also given: with the
    # command named by its path there is nothing left here for a PATH to answer.
    def self.environment = ArduinoTools.environment
  end
end
