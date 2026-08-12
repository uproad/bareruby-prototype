# frozen_string_literal: true

require "bareruby_prot/toolchain"

module BareRubyProt
  # A .uf2 carries the family id of the chip it was built for, so the image says which
  # boards are candidates and only two of the same chip need telling apart. That is what
  # flash.sh does, and it is left in the shell it was proved on real hardware in.
  #
  # **Writing a board is three things, and only the last of them is writing.** A board that
  # is running has to be rebooted into its bootloader, the bus has to be given time to
  # settle afterwards, and only then can anybody say which device is which. Done inside
  # each board's own run, the middle of that lands on a bus that every other board is also
  # moving: devices come and go between two lines of a scan, a listing is asked for and
  # comes back empty, and where the boards arrive over usbipd rather than off a bus they
  # can even come back holding each other's port.
  #
  # So the reset and the finding are done **once, for every board a run will write**, and
  # the writing — which needs nothing but a device that is already sitting still — is what
  # is left to run at the same time.
  module PicoSdkFlash
    SCRIPT = File.expand_path("flash.sh", __dir__)
    IMAGE = "bareruby_program.uf2"
    FAMILIES = { "e48bff56" => "rp2040", "e48bff57" => "rp2350" }.freeze

    # **Which chips answer to the same name in both states.** An RP2350 reports one serial
    # whether its bootloader or its firmware is running, so it can be picked out of a
    # settled bus by name. An RP2040's bootloader does not have a name of its own: three
    # boards on one desk — two of one model and one of another — all called themselves
    # E0C9125B0D9B, down to the same model, revision and size. Those can only be counted,
    # not named.
    NAMED_IN_BOOTSEL = { "rp2350" => true, "rp2040" => false }.freeze

    SETTLE_SECONDS = 100
    TICK = 0.5

    Board = Struct.new(:serial, :chip, :state, :node, :port) do
      def bootsel? = state == "bootsel"
    end

    def self.attached
      IO.popen([SCRIPT, "--attached"], &:read).lines(chomp: true).filter_map do |line|
        fields = line.split
        Board.new(*fields) if fields.length == 5
      end
    end

    # **Every board this run will write, found once and handed over.** What comes back is
    # one entry to a list of devices, ready to be written without anybody asking the bus
    # another question.
    def self.prepare(plans)
      listing = attached
      wanted = plans.to_h { |entry, directory| [entry, chosen(entry, directory, listing)] }
      return nil unless apart?(wanted)

      running = wanted.values.flatten.reject(&:bootsel?)
      return found(wanted, listing) if running.empty?

      reset(running)
      settled(listing, running) or return warned(running)
      found(wanted, attached)
    end

    # **An entry that names no board takes every board of its chip**, which is what a desk
    # with a shelf of identical boards means by saying nothing. Two entries doing that for
    # one chip are two entries asking for the same boards, and no image can say which of
    # them a board belongs to — so that is a question for the record rather than a guess
    # made here.
    def self.apart?(wanted)
      open = wanted.reject { |entry, _| entry.boards.any? }
                   .group_by { |_, boards| boards.first&.chip }
                   .select { |chip, pairs| chip && pairs.length > 1 }
      open.each do |chip, pairs|
        warn "flash: #{pairs.map { |entry, _| entry.name }.join(' and ')} each take every " \
             "#{chip} board attached, so nothing says which board is which one's."
        warn "       Name their serials under 'boards:' in config/target.yml. A running " \
             "board answers to a serial of its own; the flasher's --list prints them."
      end
      open.empty?
    end

    # Which attached boards an entry is asking for: the ones it names, or every one
    # carrying its chip.
    def self.chosen(entry, directory, listing)
      chip = chip_of(File.join(directory, IMAGE))
      carrying = listing.select { |board| board.chip == chip }
      return carrying.select { |board| entry.boards.map(&:to_s).include?(board.serial) } unless entry.boards.empty?

      carrying
    end

    # Bytes 28..31 of a .uf2 are the family id, which is the chip the image was built for.
    def self.chip_of(image)
      FAMILIES[File.binread(image, 4, 28).unpack1("V").to_s(16).rjust(8, "0")]
    end

    # **The cheap part.** Opening a port at 1200 baud is what reboots a pico-sdk firmware
    # into its bootloader, and it costs nothing to speak of: two boards measured at 0.036s
    # between them. There is nothing here worth doing at the same time.
    def self.reset(boards)
      boards.each { |board| Toolchain.aloud([SCRIPT, "--reset", board.node]) }
    end

    # **The expensive part, waited out once rather than once per board.** A board that has
    # been rebooted comes back as a different USB device, and where that arrives over
    # usbipd it has to be attached again — measured at five seconds on its own and at
    # sixty-nine with another board re-attaching beside it. Waiting for all of them
    # together is one wait instead of a wait each, and it is the wait that lets everything
    # after it look at a bus that has stopped moving.
    def self.settled(before, running)
      wanted = running.group_by(&:chip).transform_values(&:length)
      held = before.select(&:bootsel?).group_by(&:chip).transform_values(&:length)
      deadline = Time.now + SETTLE_SECONDS
      while Time.now < deadline
        now = attached.select(&:bootsel?).group_by(&:chip).transform_values(&:length)
        return true if wanted.all? { |chip, count| now.fetch(chip, 0) >= held.fetch(chip, 0) + count }

        sleep TICK
      end
      false
    end

    def self.warned(running)
      warn "flash: #{running.length} board#{'s' unless running.one?} were reset and did " \
           "not all come back within #{SETTLE_SECONDS}s."
      warn "       Where the boards arrive over usbipd, each reset re-enumerates a board " \
           "and it has to be attached again."
      nil
    end

    # **Named where a chip has a name, counted where it does not.** An RP2350 is picked out
    # of the settled listing by its serial, which it kept across the reset. An RP2040 has
    # nothing to be picked out by, so what is left of its chip is handed out one board to
    # one asking — which is right as long as the boards asking take the same image, and is
    # the reason two of them that do not are not written at the same time.
    def self.found(wanted, listing)
      pool = listing.select(&:bootsel?)
      wanted.to_h do |entry, boards|
        [entry, boards.filter_map { |board| claim(board, pool) }]
      end
    end

    def self.claim(board, pool)
      taken = if NAMED_IN_BOOTSEL[board.chip]
                pool.find { |one| one.serial == board.serial } || pool.find { |one| one.chip == board.chip }
              else
                pool.find { |one| one.chip == board.chip }
              end
      pool.delete(taken)
      taken
    end

    # What is left once a device has been found: the copy, and nothing that asks the bus
    # anything. Several of these run at the same time.
    def self.run(directory, boards:, options: {}, found: nil)
      image = File.join(directory, IMAGE)
      return by_hand(image, boards) if found.nil?
      return false if found.empty?

      written(found, image)
    end

    # **The boards of one entry are written at the same time as each other.** They take the
    # same image and they were found before any of this started, so there is nothing left
    # for them to take from one another: each one is a copy onto a device already sitting
    # still. A shelf of identical boards is the case this is for, and it is the one a run
    # writing them in turn made you wait through.
    #
    # Threads rather than processes: every one of these is waiting on a program of somebody
    # else's, which is the wait Ruby lets go of.
    def self.written(found, image)
      found.map { |board| Thread.new { Toolchain.aloud([SCRIPT, "--device", board.node, image]) } }
           .map(&:value).all?
    end

    # Reached where nobody prepared anything — the flasher run on its own, which does all
    # three of its own steps because it is writing one board and nothing else is moving.
    def self.by_hand(image, boards)
      return Toolchain.aloud([SCRIPT, image]) if boards.empty?

      boards.all? { |board| Toolchain.aloud([SCRIPT, "--board", board.to_s, image]) }
    end
  end
end
