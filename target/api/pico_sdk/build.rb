# frozen_string_literal: true

require_relative "binding"

module BareRubyProt
  # How the second stage builds a program for a board: pico-sdk through cmake, the record
  # of what that build is, and the flags that decide what the firmware carries.
  class PicoSdkBuild
    SDK_LIBRARIES = %w[pico_stdlib hardware_adc hardware_gpio hardware_pwm hardware_uart
                       hardware_i2c hardware_clocks].freeze

    # A board starts the SDK before the program and has nowhere to return to, so it
    # idles rather than ending.
    ENTRY = "int main(void) {\n    bareruby_startup();\n    bareruby_main();\n    for (;;) {\n" \
            "        bareruby_sleep_ms(1000);\n    }\n}\n"

    def initialize(target, sources:, onboard_led:, debug:, exceptions:)
      @target = target
      @sources = sources
      @onboard_led = onboard_led
      @debug = debug
      @exceptions = exceptions
    end

    def files = { "manifest.txt" => manifest, "CMakeLists.txt" => cmake_lists }

    # Without a debug build there is no channel for output to leave by, so a puts has
    # nowhere to arrive and the generated code does not make the call.
    def stdout? = @debug

    def entry = ENTRY

    def manifest
      <<~MANIFEST
        target = #{@target.name}
        board = #{@target.machine.name}
        triple = #{@target.isa.triple}
        chip = #{@target.machine.chip}
        toolchain = arm-none-eabi-g++
        language_standard = gnu++20
        compile_options = -std=gnu++20 -fno-rtti
        include_directories = ..
        sources = #{@sources.join(' ')}
        link_libraries = #{libraries.join(' ')}
        stdout_channel = #{stdout? ? 'usb' : 'none'}
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
      return SDK_LIBRARIES unless @onboard_led

      SDK_LIBRARIES + PicoSdkBinding.machine(@target.machine).onboard_led_libraries
    end

    def cmake_lists
      <<~CMAKE
        cmake_minimum_required(VERSION 3.13)

        # The board picks the chip, the linker script and the register headers, so it has
        # to be set before the SDK is imported rather than passed to the build later.
        set(PICO_BOARD #{@target.machine.name})
        set(PICO_PLATFORM #{@target.machine.chip})

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

        target_include_directories(bareruby_program PRIVATE ..)
        target_compile_options(bareruby_program PRIVATE $<$<COMPILE_LANGUAGE:CXX>:-fno-rtti#{@exceptions ? '' : ' -fno-exceptions'}>)
        target_link_libraries(bareruby_program #{libraries.join(' ')})
        #{stdio_text}
        pico_add_extra_outputs(bareruby_program)
      CMAKE
    end

    def stdio_text
      return "\npico_enable_stdio_usb(bareruby_program 0)\npico_enable_stdio_uart(bareruby_program 0)\n" unless @debug

      <<~CMAKE

        pico_enable_stdio_usb(bareruby_program 1)
        pico_enable_stdio_uart(bareruby_program 0)

        # Keep the USB device enumerated so the board can be reset into BOOTSEL from
        # the host instead of by replugging it with the button held.
        target_compile_definitions(bareruby_program PRIVATE
            PICO_STDIO_USB_ENABLE_RESET_VIA_BAUD_RATE=1
            PICO_STDIO_USB_RESET_MAGIC_BAUD_RATE=1200
            PICO_STDIO_USB_ENABLE_RESET_VIA_VENDOR_INTERFACE=1
        )
      CMAKE
    end
  end
end
