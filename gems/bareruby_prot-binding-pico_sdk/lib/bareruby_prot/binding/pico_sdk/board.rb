# frozen_string_literal: true

require "bareruby_prot/toolchain"

require_relative "binding"
require_relative "flash"

module BareRubyProt
  # **Attaching a board is telling it what it is called.** The name goes into a page of the
  # board's own flash, and the firmware reads it back and hands it to the host as its USB
  # serial number — after which the desk finds this board by asking for the name a target
  # record already gives it, and nothing is left to be inferred from ports, from the order
  # devices arrived in, or from a bootloader id three identical boards share.
  #
  # **It is done once per board, through BOOTSEL, and the button is what says which board.**
  # There is nothing else that could say it: before a board has a name, one RP2040 in a
  # bootloader is indistinguishable from the next, so the choice is made by hand — hold the
  # button on the board being named. Afterwards it never has to be made again.
  #
  # The page and the program travel in one file. Writing the page on its own would leave
  # the board running whatever firmware it already had, unnamed, and needing to be found a
  # second time — which is the problem this is here to end, faced once more on the way out
  # of it.
  module PicoSdkBoard
    # What `target attach` leaves beside the image it was built from. It is the image plus
    # one block, so it is named for the errand rather than for the program.
    IMAGE = "bareruby_attach.uf2"

    # A .uf2 is a stream of fixed blocks: a 32-byte header, 476 bytes of room for a payload,
    # and a mark at the end. The bootloader takes each block as it arrives and writes the
    # payload at the address the header names.
    BLOCK_SIZE = 512
    HEADER_SIZE = 32
    PAYLOAD_SIZE = 256
    MAGIC_START0 = 0x0a32_4655
    MAGIC_START1 = 0x9e5d_5157
    MAGIC_END = 0x0ab1_6f30
    FAMILY_ID_PRESENT = 0x0000_2000

    # Where flash appears to the processor, and the smallest span of it that can be erased.
    # The page is the first of the last sector, which is the same address the firmware
    # reads — spelled here in Ruby and there through the SDK's own names.
    XIP_BASE = 0x1000_0000
    SECTOR_SIZE = 4096

    # What is written into the page: a mark that says a name is there at all, then the name
    # itself, then the rest of the page left as an erased sector reads.
    MARK = "BARERUBY"
    NAME_SIZE = 32
    UNWRITTEN = "\xff".b

    # **What the bootloader is told the page is.** A family id says which chip a block was
    # built for, and an RP2350 has one more: `e48bff57` means the block belongs to no image
    # at all and goes at the address it names, which is what a page of loose data is. An
    # RP2040 predates that and knows only its own — which serves, because it has no image
    # rules to be outside of. **Measured**: an RP2350 given the page under `e48bff59`, the
    # family its program carries, wrote the program and silently dropped the page.
    LOOSE = { "rp2040" => 0xe48b_ff56, "rp2350" => 0xe48b_ff57 }.freeze

    # **One block offered where two are announced, on purpose.** The bootloader reboots the
    # board the moment a download is complete, and a complete download of one block would
    # reboot it before the program behind it in this file had arrived. Announcing a block
    # that never comes leaves the download open until the program's own blocks replace it —
    # which is the same trick pico-sdk plays with the block it puts in front of an RP2350
    # image.
    BLOCKS_ANNOUNCED = 2

    # **Which board this is for, asked before anything is built.** The button is something a
    # person did a moment ago, and a run that compiles for ten seconds before saying it was
    # not pressed has sat on the one thing it could have said at once. Nothing is read off
    # the image to answer this — which chip an entry is for is the machine's own answer.
    def self.waiting(target)
      chip = target.machine.chip
      found = PicoSdkFlash.attached.select { |board| board.bootsel? && board.chip == chip }
      found.one? ? found.first : by_hand(chip, found)
    end

    def self.attach(name:, target:, directory:, board:)
      image = File.join(directory, PicoSdkFlash::IMAGE)
      attached = File.join(directory, IMAGE)
      File.binwrite(attached, block(name, target) + File.binread(image))
      Toolchain.aloud([PicoSdkFlash::SCRIPT, "--device", board.node, attached])
    end

    # **The button is the question, so this asks for it rather than choosing.** None and
    # several are the same answer from here: nothing on the bus says which board was meant.
    def self.by_hand(chip, waiting)
      warn "attach: #{waiting.empty? ? "no #{chip} board is" : "#{waiting.length} #{chip} " \
           'boards are'} in BOOTSEL, so nothing says which board this name is for."
      warn "        Hold BOOTSEL down, plug the board in, and run this again. Leave every " \
           "other #{chip} board out of BOOTSEL: until a board carries a name there is " \
           "nothing else to tell it by."
      nil
    end

    # The block the page travels in. Everything about it is fixed but three fields: where
    # it goes, which chip will take it, and what it says.
    def self.block(name, target)
      header = [MAGIC_START0, MAGIC_START1, FAMILY_ID_PRESENT, address(target),
                PAYLOAD_SIZE, 0, BLOCKS_ANNOUNCED, LOOSE.fetch(target.machine.chip)].pack("V8")
      padding = BLOCK_SIZE - HEADER_SIZE - PAYLOAD_SIZE - 4
      header + page(name) + ("\0" * padding) + [MAGIC_END].pack("V")
    end

    # The name is cut to what the page holds and always ends in a terminator, so the
    # firmware reads a string rather than the rest of the sector. Bytes throughout — what
    # is being made here is a page of flash, and 0xFF is not a character.
    def self.page(name)
      "#{MARK}#{name.to_s[0, NAME_SIZE - 1]}\0".b.ljust(PAYLOAD_SIZE, UNWRITTEN)
    end

    def self.address(target)
      XIP_BASE + PicoSdkBinding.machine(target.machine).flash_bytes - SECTOR_SIZE
    end
  end
end
