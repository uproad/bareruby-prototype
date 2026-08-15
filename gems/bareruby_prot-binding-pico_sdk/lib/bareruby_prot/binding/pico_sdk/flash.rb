# frozen_string_literal: true

require "bareruby_prot/toolchain"

module BareRubyProt
  # A .uf2 carries the family id of the chip it was built for, so the image says which
  # boards are candidates and only two of the same chip need telling apart. That is what
  # flash.sh does, and it is left in the shell it was proved on real hardware in.
  #
  # **A named running board does not need its bootloader to take a program.** Its resident
  # listener stages the bytes and replaces the image itself, so its serial still says
  # exactly which board is being written. An unnamed running board still has to be reset
  # into BOOTSEL, the bus has to be given time to settle afterwards, and only then can
  # anybody say which device is which. Done inside each board's own run, that middle step
  # lands on a bus that every other board is also moving: devices come and go between two
  # lines of a scan, a listing is asked for and comes back empty, and where the boards
  # arrive over usbipd rather than off a bus they can even come back holding each other's
  # port.
  #
  # So any reset and the finding are done **once, for every board a run will write**, and
  # the writing — over a named port or onto a bootloader volume already sitting still — is
  # what is left to run at the same time.
  module PicoSdkFlash
    SCRIPT = File.expand_path("flash.sh", __dir__)
    IMAGE = "bareruby_program.uf2"
    FAMILIES = { "e48bff56" => "rp2040", "e48bff57" => "rp2350" }.freeze
    PROGRAM_FAMILIES = { "rp2040" => "e48bff56", "rp2350" => "e48bff59" }.freeze

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
      names = plans.map { |entry, _| entry.name }
      wanted = plans.to_h { |entry, directory| [entry, chosen(entry, directory, listing, names)] }
      return nil unless apart?(wanted)

      running = wanted.values.flatten.reject(&:bootsel?)
      return found(wanted, listing) if running.empty?

      running = running.reject { |board| board.serial == entry_of(wanted, board)&.name }
      return found(wanted, listing) if running.empty?

      reset(running)
      # **What came back is what is written.** A board that has not returned inside the
      # window is one row's bad news, not the run's: the others are sitting in their
      # bootloaders waiting, and failing them for its sake is failing work that was ready.
      warned(running) unless settled(listing, running)
      found(wanted, attached)
    end

    # **An entry that names no board takes every board of its chip**, which is what a desk
    # with a shelf of identical boards means by saying nothing. Two entries doing that for
    # one chip are two entries asking for the same boards, and no image can say which of
    # them a board belongs to — so that is a question for the record rather than a guess
    # made here.
    def self.apart?(wanted)
      open = wanted.reject { |entry, boards| settled?(entry, boards) }
                   .group_by { |_, boards| boards.first&.chip }
                   .select { |chip, pairs| chip && pairs.length > 1 }
      open.each do |chip, pairs|
        named = pairs.map { |entry, _| entry.name }
        warn "flash: #{named.join(' and ')} each take every #{chip} board attached, so " \
             "nothing says which board is which one's."
        warn "       Give each board the name of the entry it belongs to. That is one " \
             "command a board, and it settles this for good:"
        named.each { |one| warn "         bareruby target attach --target=#{one}" }
        warn "       Or name their serials under 'boards:' in config/target.yml — a " \
             "running board answers to a serial of its own, and the flasher's --list " \
             "prints them."
      end
      open.empty?
    end

    # An entry is settled either because the record named its boards or because a board is
    # answering to its name, and the second is the one `target attach` exists to arrange.
    # Counting only the first is what left an entry whose board was standing right there
    # being asked which of two it meant.
    def self.settled?(entry, boards)
      entry.boards.any? || boards.any? { |board| board.serial == entry.name }
    end

    # Which attached boards an entry is asking for: the ones it names, or every one
    # carrying its chip.
    # **An explicit list is the complete answer.** It can deliberately put several boards
    # behind one entry, including the board whose name equals the entry, so it must be
    # considered before that convenient single-board match.
    #
    # **A board that carries a name has already said whose it is.** With no explicit list,
    # a board answering to this entry's name is this entry's, whatever else is attached.
    #
    # **And it is not anybody else's.** An entry naming no board takes every board of its
    # chip, which used to mean every board including ones plainly spoken for — a shelf
    # holding a board called `pico` and a board called `pico2` left `pico2w` reporting two
    # candidates and refusing, when one of them had been answering to another entry all
    # along. What is left over is what an entry naming nothing takes.
    def self.chosen(entry, directory, listing, names = [])
      chip = chip_of(File.join(directory, IMAGE))
      carrying = listing.select { |board| board.chip == chip }
      return carrying.select { |board| entry.boards.map(&:to_s).include?(board.serial) } unless entry.boards.empty?

      answering = carrying.select { |board| board.serial == entry.name }
      return answering unless answering.empty?

      carrying.reject { |board| (names - [entry.name]).include?(board.serial) }
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

    # Said by the row it happened to, rather than by the run. The board was reset and did
    # not come back inside the window; every other row got on with its own board.
    def self.nothing_came_back
      warn "flash: this board was reset and did not come back in time to be written."
      warn "       Where the boards arrive over usbipd, each reset re-enumerates a board " \
           "and it has to be attached again; several at once is what it keeps up with least."
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
      # **Running boards are handed out too**, because a board that says its name takes its
      # program without ever going to its bootloader. Only boards that had to be reset are
      # waiting in one.
      pool = listing.dup
      wanted.to_h do |entry, boards|
        [entry, boards.filter_map { |board| claim(board, pool) }]
      end
    end

    def self.claim(board, pool)
      taken = pool.find { |one| one.serial == board.serial } ||
              pool.select(&:bootsel?).find { |one| one.chip == board.chip }
      pool.delete(taken)
      taken
    end

    # What is left once a device has been found: the copy, and nothing that asks the bus
    # anything. Several of these run at the same time.
    def self.run(directory, boards:, options: {}, found: nil)
      image = File.join(directory, IMAGE)
      return by_hand(image, boards) if found.nil?
      return nothing_came_back if found.empty?

      written(found, image)
    end

    def self.entry_of(wanted, board)
      wanted.find { |_, boards| boards.include?(board) }&.first
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
      found.map { |board| Thread.new { one(board, image) } }.map(&:value).all?
    end

    # **A board that is running and says its name takes its next program over the wire it
    # is already talking on.** Nothing is reset, nothing re-enumerates while the handing
    # over happens, and the name — which lives in this board's firmware and not in the
    # chip's ROM — is there before and after. A board in its bootloader is written the old
    # way, which is what the first program of all arrives by.
    def self.one(board, image)
      board.bootsel? ? Toolchain.aloud([SCRIPT, "--device", board.node, image]) : streamed(board, image)
    end

    STREAM_MARK = "BRLOAD"
    STREAM_DONE = "BRDONE"
    STREAM_BAUD = "115200"
    STREAM_SECONDS = 60
    REBOOT_TICK = 0.05

    def self.streamed(board, image)
      bytes = flat(image)
      warn "flash: #{board.serial} takes #{bytes.bytesize} bytes over #{board.node}"
      system("stty", "-F", board.node, "raw", "-echo", STREAM_BAUD, %i[out err] => File::NULL)
      File.open(board.node, "r+b") do |port|
        port.write(format("%s%08x", STREAM_MARK, bytes.bytesize))
        port.write(bytes)
        port.flush
        return false unless said(port, board)
      end
      back(board)
    end

    # **The board says it has the whole program before it moves it into place**, and that
    # is the only thing that says so. A board answering to its name afterwards proves
    # nothing on its own: it was answering to it beforehand too, so a run that sent
    # nothing at all would look exactly like one that worked. What is waited for is the
    # board's own word, said among whatever the program running on it is also saying.
    def self.said(port, board)
      deadline = Time.now + STREAM_SECONDS
      held = +""
      while Time.now < deadline
        break unless IO.select([port], nil, nil, TICK)

        held << port.readpartial(BUFFER)
        return true if held.include?(STREAM_DONE)
      end
      warn "flash: #{board.serial} did not say it had the program."
      false
    end

    BUFFER = 4096

    # **The old port has to leave before the new one can count as back.** The board says
    # BRDONE, waits 200 ms, and only then reboots. Seeing its name during that wait is
    # still seeing the firmware about to disappear; accepting it made a flash finish just
    # before the USB device left, so an immediately following run found no board at all.
    def self.back(board)
      deadline = Time.now + STREAM_SECONDS
      left = false
      while Time.now < deadline
        present = attached.any? { |one| one.serial == board.serial && !one.bootsel? }
        left ||= !present
        return true if left && present

        sleep REBOOT_TICK
      end
      warn "flash: #{board.serial} did not come back after taking its program."
      false
    end

    # A .uf2 is addressed blocks of 256 bytes; what a board takes is the program family's
    # bytes in address order. An RP2350 file also starts with an absolute-family metadata
    # block at 0x10ffff00. The bootloader consumes that envelope, but it is not one of the
    # bytes that belong at the start of flash.
    def self.flat(image)
      blocks = File.binread(image).unpack("a512" * (File.size(image) / 512))
      family = PROGRAM_FAMILIES.fetch(chip_of(image)).to_i(16)
      blocks.select { |block| block[28, 4].unpack1("V") == family }
            .sort_by { |block| block[12, 4].unpack1("V") }
            .map { |block| block[32, block[16, 4].unpack1("V")] }.join
    end

    # Reached where nobody prepared anything — the flasher run on its own, which does all
    # three of its own steps because it is writing one board and nothing else is moving.
    def self.by_hand(image, boards)
      return Toolchain.aloud([SCRIPT, image]) if boards.empty?

      boards.all? { |board| Toolchain.aloud([SCRIPT, "--board", board.to_s, image]) }
    end
  end
end
