# frozen_string_literal: true

require_relative "binding"

module BareRubyProt
  # How the second stage builds a program for a board: pico-sdk through cmake, the record
  # of what that build is, and the flags that decide what the firmware carries.
  class PicoSdkBuild
    # pico_flash and pico_multicore are what the resident update unit is built out of:
    # the other core listens, and writing flash while a program runs is a thing the SDK
    # arranges rather than a thing anybody does by hand.
    SDK_LIBRARIES = %w[pico_stdlib hardware_adc hardware_gpio hardware_pwm hardware_uart
                       hardware_i2c hardware_clocks hardware_flash hardware_watchdog
                       hardware_sync pico_flash pico_multicore].freeze

    # A board starts the SDK before the program and has nowhere to return to, so it
    # idles rather than ending.
    ENTRY = "int main(void) {\n    bareruby_startup();\n    bareruby_main();\n    for (;;) {\n" \
            "        bareruby_sleep_ms(1000);\n    }\n}\n"

    def initialize(target, sources:, units:, debug:, exceptions:)
      @target = target
      @sources = sources
      @units = units
      @debug = debug
      @exceptions = exceptions
    end

    def files
      { "manifest.txt" => manifest, "CMakeLists.txt" => cmake_lists,
        PicoSdkBinding::TUSB_CONFIG_FILE => PicoSdkBinding::TUSB_CONFIG }
    end

    # Without a debug build there is no channel for output to leave by, so a puts has
    # nowhere to arrive and the generated code does not make the call.
    def stdout? = @debug

    def entry = ENTRY

    def manifest
      <<~MANIFEST
        target = #{@target.name}
        board = #{@target.machine.key}
        triple = #{@target.isa.triple}
        chip = #{@target.machine.chip}
        toolchain = arm-none-eabi-g++
        language_standard = gnu++20
        compile_options = -std=gnu++20 -fno-rtti
        link_time_optimization = enabled
        include_directories = ..
        sources = #{@sources.join(' ')}
        link_libraries = #{libraries.join(' ')}
        stdout_channel = #{stdout? ? 'usb' : 'none'}
        usb_descriptors = #{stdout? ? 'own' : 'none'}
        debug = #{@debug ? 'enabled' : 'disabled'}
        exceptions = #{@exceptions ? 'enabled' : 'disabled'}
        artifact = bareruby_program.uf2
        build_command = cmake -B build -S . && cmake --build build
      MANIFEST
    end

    # The radio's driver is linked only by a board that reaches its indicator through the
    # radio and by a program that actually lights it, so the firmware blob it carries is
    # not a tax on every build for that board. What a board needs linked is the cell's
    # answer, not this file's.
    def libraries
      return SDK_LIBRARIES unless @units.include?(:onboard_led)

      SDK_LIBRARIES + PicoSdkBinding.machine(@target.machine).onboard_led_libraries
    end

    def cmake_lists
      <<~CMAKE
        cmake_minimum_required(VERSION 3.13)

        # The board picks the chip, the linker script and the register headers, so it has
        # to be set before the SDK is imported rather than passed to the build later.
        set(PICO_BOARD #{PicoSdkBinding.machine(@target.machine).pico_board})
        set(PICO_PLATFORM #{PicoSdkBinding.machine(@target.machine).pico_platform})

        include($ENV{PICO_SDK_PATH}/external/pico_sdk_import.cmake)

        # pico-sdk leaves C++ exceptions off unless asked, so whether the unwinder and
        # its tables are linked is a decision the first stage records here.
        set(PICO_CXX_ENABLE_EXCEPTIONS #{@exceptions ? 1 : 0})

        project(bareruby_program C CXX ASM)
        set(CMAKE_C_STANDARD 11)
        set(CMAKE_CXX_STANDARD 20)

        pico_sdk_init()

        add_executable(bareruby_program
        #{@sources.map { |source| "    #{source}" }.join("\n")}
        )

        target_include_directories(bareruby_program BEFORE PRIVATE ${CMAKE_CURRENT_LIST_DIR} ..)
        target_compile_options(bareruby_program PRIVATE $<$<COMPILE_LANGUAGE:CXX>:-fno-rtti#{@exceptions ? '' : ' -fno-exceptions'}>)
        target_link_libraries(bareruby_program #{libraries.join(' ')})

        # Each peripheral is a translation unit of its own, so a pin write is a call
        # across one where the hardware asks for a single store. Nothing this side can
        # see undoes that — the caller and the callee are never in front of the compiler
        # at the same time — so it is handed to the linker, which has both. This is the
        # whole reason the first stage emits C++ rather than instructions: the optimizer
        # is somebody else's and already written.
        #
        # **Only the units this build generated.** Asked of the target instead, it would
        # take pico-sdk's sources with it, and the SDK reaches its own stdio through
        # -Wl,--wrap: a wrapper nothing calls in the IR is dropped before the linker makes
        # the reference that would have kept it. Naming the 160 symbols it wraps would
        # link every one of them into every program. The boundary that matters here is the
        # one between generated units anyway — past it, the build is somebody else's.
        set_source_files_properties(
        #{@sources.map { |source| "    #{source}" }.join("\n")}
            PROPERTIES COMPILE_OPTIONS "-flto")

        target_link_options(bareruby_program PRIVATE -flto)
        #{stdio_text}
        pico_add_extra_outputs(bareruby_program)
      CMAKE
    end

    def stdio_text
      return "\npico_enable_stdio_usb(bareruby_program 0)\npico_enable_stdio_uart(bareruby_program 0)\n" unless @debug

      <<~CMAKE

        pico_enable_stdio_usb(bareruby_program 1)
        pico_enable_stdio_uart(bareruby_program 0)

        # Keep the CDC device enumerated so opening it at 1200 baud can reset the board
        # into BOOTSEL instead of requiring the button. The extra vendor reset interface
        # is not involved in that path and would consume endpoints on every attached board.
        #
        # **And let the board name itself.** pico-sdk's own descriptors say "Pico" made by
        # "Raspberry Pi" and nothing that tells one board from another; switching them off
        # is what lets the identity unit answer with the name written into the board's
        # flash, which is the one thing a desk can ask for. Everything else about the
        # descriptors — including the ids used to tell an RP2040 from an RP2350 — is
        # unchanged.
        target_compile_definitions(bareruby_program PRIVATE
            BARERUBY_USB_PRODUCT="#{PicoSdkBinding.machine(@target.machine).usb_product}"
            PICO_STDIO_USB_ENABLE_RESET_VIA_BAUD_RATE=1
            PICO_STDIO_USB_RESET_MAGIC_BAUD_RATE=1200
            PICO_STDIO_USB_ENABLE_RESET_VIA_VENDOR_INTERFACE=0
            PICO_STDIO_USB_USE_DEFAULT_DESCRIPTORS=0
        )
      CMAKE
    end
  end
end
