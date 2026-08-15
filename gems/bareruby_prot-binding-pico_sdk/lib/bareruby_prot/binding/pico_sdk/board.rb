# frozen_string_literal: true

require "fileutils"

require "bareruby_prot/toolchain"

require_relative "binding"
require_relative "flash"
require_relative "toolchain"

module BareRubyProt
  # **Attaching a board is telling it what it is called.** The name goes into a page of the
  # board's own flash, and the firmware reads it back and hands it to the host as its USB
  # serial number — after which the desk finds this board by asking for the name a target
  # record already gives it, and nothing is left to be inferred from ports, from the order
  # devices arrived in, or from a bootloader id three identical boards share.
  #
  # **No program of the user's is anywhere in this.** What is written beside the name is the
  # agent: firmware belonging to this binding that brings USB up, says what the board is
  # called, and waits. Programs arrive later and by another verb — `deploy` and `flash` are
  # what carry those — so naming a board never asks anybody which program they meant. Its
  # resident logic is shared; its attach image carries the requested name for the first boot.
  #
  # The name has to travel with a firmware rather than on its own, because a page written by
  # itself would leave the board running whatever it ran before, unnamed, and needing to be
  # found a second time — which is the problem this is here to end, met again on the way out
  # of it. The agent is what makes that firmware something this side can supply.
  #
  # **It is done once per board, through BOOTSEL, and the button is what says which board.**
  # There is nothing else that could say it: before a board has a name, one RP2040 in a
  # bootloader is indistinguishable from the next, so the choice is made by hand. Afterwards
  # it never has to be made again.
  module PicoSdkBoard
    # What the agent is called wherever it is written down: the cmake project, the image it
    # leaves, and the file the name page is prepended to.
    AGENT = "bareruby_agent"
    IMAGE = "#{AGENT}.uf2"
    ATTACH_IMAGE = "#{AGENT}_named.uf2"

    # The agent's own translation unit. It brings USB up — which is what the identity unit
    # beside it needs in order to be asked anything — and then waits, because a board that
    # has been named and not yet deployed to is a board waiting for a program.
    #
    # **This is where the resident runtime begins.** Everything a board does that is not the
    # user's program belongs here rather than in an image the compiler produced.
    PROGRAM = <<~CPP
      #include "pico/stdlib.h"

      extern "C" void bareruby_agent_attach(const uint8_t *name, size_t length);
      extern "C" void bareruby_agent_start(void);

      int main(void) {
          static const uint8_t name[] = { BARERUBY_AGENT_NAME_BYTES };
          bareruby_agent_attach(name, sizeof(name));
          stdio_init_all();
          bareruby_agent_start();
          for (;;) {
              sleep_ms(1000);
          }
      }
    CPP

    PROGRAM_FILE = "main.cpp"
    IDENTITY_FILE = "identity.cpp"

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
    # reboot it before the agent behind it in this file had arrived. Announcing a block that
    # never comes leaves the download open until the agent's own blocks replace it — which
    # is the same trick pico-sdk plays with the block it puts in front of an RP2350 image.
    BLOCKS_ANNOUNCED = 2

    # **Which board this is for, asked before anything is built.** The button is something a
    # person did a moment ago, and a run that compiles for ten seconds before saying it was
    # not pressed has sat on the one thing it could have said at once. Which chip an entry
    # is for is the machine's own answer, so nothing has to be built to ask this either.
    def self.waiting(target)
      chip = target.machine.chip
      found = PicoSdkFlash.attached.select { |board| board.bootsel? && board.chip == chip }
      found.one? ? found.first : by_hand(chip, found)
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

    # The agent, built for this machine. Its ordinary resident code reads the name as data
    # from the reserved page. The attach build also carries that name long enough to repair
    # the page on first boot, because flash that once held another name cannot set its zero
    # bits back to one merely by accepting another UF2 block.
    def self.build(target, directory, name)
      FileUtils.mkdir_p(directory)
      files(target, name).each { |file, text| File.write(File.join(directory, file), text) }
      return nil unless Toolchain.as_recorded(directory, PicoSdkToolchain.environment)

      File.join(directory, "build", IMAGE)
    end

    def self.files(target, name)
      bytes = name.to_s[0, NAME_SIZE - 1].bytes.join(", ")
      { PROGRAM_FILE => PROGRAM.sub("BARERUBY_AGENT_NAME_BYTES", bytes),
        IDENTITY_FILE => PicoSdkBinding::IDENTITY,
        "manifest.txt" => manifest(target, name), "CMakeLists.txt" => cmake_lists(target) }
    end

    def self.attach(name:, target:, directory:, board:)
      image = build(target, directory, name) or return false

      named = File.join(directory, "build", ATTACH_IMAGE)
      File.binwrite(named, block(name, target) + File.binread(image))
      Toolchain.aloud([PicoSdkFlash::SCRIPT, "--device", board.node, named])
    end

    # The agent is built the way every other artifact here is: a manifest saying what it is
    # and what turns it into one, read back by whoever runs the second stage.
    def self.manifest(target, name)
      <<~MANIFEST
        target = agent
        board = #{target.machine.key}
        chip = #{target.machine.chip}
        attached_name = #{name.to_s[0, NAME_SIZE - 1]}
        toolchain = arm-none-eabi-g++
        sources = #{PROGRAM_FILE} #{IDENTITY_FILE}
        stdout_channel = usb
        usb_descriptors = own
        artifact = #{IMAGE}
        build_command = cmake -B build -S . && cmake --build build
      MANIFEST
    end

    # **The USB half of what a program's build sets, and nothing else.** There is no user
    # code here to link peripherals for, no exceptions decision to carry, and no debug flag
    # to honour — an agent that did not present USB would have nothing to say its name on,
    # so this build is the one that has no choice to record.
    def self.cmake_lists(target)
      machine = PicoSdkBinding.machine(target.machine)
      <<~CMAKE
        cmake_minimum_required(VERSION 3.13)

        set(PICO_BOARD #{machine.pico_board})
        set(PICO_PLATFORM #{machine.pico_platform})

        include($ENV{PICO_SDK_PATH}/external/pico_sdk_import.cmake)

        project(#{AGENT} C CXX ASM)
        set(CMAKE_C_STANDARD 11)
        set(CMAKE_CXX_STANDARD 20)

        pico_sdk_init()

        add_executable(#{AGENT} #{PROGRAM_FILE} #{IDENTITY_FILE})
        target_compile_options(#{AGENT} PRIVATE $<$<COMPILE_LANGUAGE:CXX>:-fno-rtti -fno-exceptions>)
        target_link_libraries(#{AGENT}
            pico_stdlib
            hardware_flash
            hardware_watchdog
            hardware_sync
            pico_flash
            pico_multicore
        )

        pico_enable_stdio_usb(#{AGENT} 1)
        pico_enable_stdio_uart(#{AGENT} 0)

        # The board is reset into BOOTSEL over the port rather than by the button from here
        # on, and it answers with the name in its flash rather than with pico-sdk's own
        # descriptors — which is the whole of why this firmware exists.
        target_compile_definitions(#{AGENT} PRIVATE
            PICO_STDIO_USB_ENABLE_RESET_VIA_BAUD_RATE=1
            PICO_STDIO_USB_RESET_MAGIC_BAUD_RATE=1200
            PICO_STDIO_USB_ENABLE_RESET_VIA_VENDOR_INTERFACE=1
            PICO_STDIO_USB_USE_DEFAULT_DESCRIPTORS=0
        )

        pico_add_extra_outputs(#{AGENT})
      CMAKE
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
