# frozen_string_literal: true

require "json"

require "bareruby_prot/toolchain"
require_relative "tools"

module BareRubyProt
  # A board reached through this SDK is written to over the same serial port it talks on,
  # and the port is what identifies it — there is no volume to copy onto and no image to
  # read the chip out of while it is running.
  #
  # Which port, though, is not a guess worth making: several boards can be attached and
  # only some of them are an ESP32. So the ports are asked which USB device brought them
  # up, the ones a board of this family is reached through are kept, and a port is named in
  # target.yml only when that answer is more than one.
  #
  # **One image at one offset**, because the build already merged the three a board takes
  # into the one the offsets describe. What the board is given carries its own flash mode,
  # frequency and size in its header, so `keep` is what this side has to say about all
  # three: the build decided them and nothing here is in a position to decide better.
  module EspIdfFlash
    BAUD = "460800"

    def self.run(directory, boards:, options: {}, found: nil)
      chip = Toolchain.recorded(directory, "chip")
      ports = boards.empty? ? attached(chip) : boards.map(&:to_s)
      return false if ports.empty?

      ports.all? do |port|
        Toolchain.aloud([EspIdfTools.command("esptool.py"), "--chip", chip, "--port", port, "--baud", BAUD,
                         "--before", "default_reset", "--after", "hard_reset", "write_flash",
                         "--flash_mode", "keep", "--flash_freq", "keep", "--flash_size", "keep",
                         "0x0", File.join(directory, EspIdfToolchain::IMAGE)], environment)
      end
    end

    # **The bridges an ESP32 board is reached through**, by the vendor that made each: the
    # chip's own USB device on a board wired for it, and the three USB-to-serial chips the
    # boards that are not carry instead. It is a fact about the boards rather than about
    # the SDK, and it is the only thing that keeps a Pico on the next port from ever being
    # a candidate.
    VENDORS = [0x303a, 0x1a86, 0x10c4, 0x0403].freeze

    # **Asked until the bus is done moving, rather than once.** A board is identified here
    # by the serial port it brought up, and the ports are renumbered whenever anything on
    # the bus arrives or leaves — which is exactly what a board being written elsewhere
    # does as it resets. Asked once at the wrong moment the answer is that this board is
    # not attached, which is a different thing from what is true.
    ATTEMPTS = 20
    PAUSE = 0.5

    def self.attached(chip)
      ports = []
      ATTEMPTS.times do
        ports = candidates
        break unless ports.empty?

        sleep PAUSE
      end
      return ports if ports.length == 1

      warn(if ports.empty?
             "flash: no attached port is a board an #{chip} is reached through."
           else
             "flash: #{ports.length} attached ports could be that board, so nothing says " \
             "which one to write. Name a port in target.yml: #{ports.join(', ')}"
           end)
      []
    end

    # The ports this desk has, asked of the library that already answers it. It came with
    # ESP-IDF's own Python environment, which is where every other question about these
    # boards is asked too.
    LISTING = "import json, serial.tools.list_ports as ports; " \
              "print(json.dumps([[one.device, one.vid] for one in ports.comports()]))"

    def self.candidates
      listing = IO.popen(environment, [EspIdfTools.command("python"), "-c", LISTING], &:read)
      JSON.parse(listing).select { |_, vendor| VENDORS.include?(vendor) }.map(&:first).sort
    end

    def self.environment = EspIdfTools.environment
  end
end
