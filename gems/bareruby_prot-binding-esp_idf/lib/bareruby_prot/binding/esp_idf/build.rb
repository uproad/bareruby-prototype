# frozen_string_literal: true

require_relative "binding"

module BareRubyProt
  # How the second stage builds a program for a board reached through ESP-IDF: a cmake
  # project the SDK's own `project.cmake` drives, one component holding the translation
  # units this program reached for, and the record of what that build is.
  #
  # **FreeRTOS owns main and calls `app_main`**, so this side supplies that rather than an
  # entry point of its own — the same shape the STM32Cube binding is in, and the reason the
  # program's translation unit is named after the program.
  class EspIdfBuild
    # The component ESP-IDF looks for by name. A project has one, it is where the program
    # goes, and everything else in the build is a component the SDK brought.
    COMPONENT = "main"

    # `app_main` is called by a task FreeRTOS started, and returning from it deletes that
    # task while the system carries on — so a board has nowhere to return to here either.
    # It idles instead, and the idling still delivers: a handler a program registered
    # outlives the program, and this is the only wait left to run it in.
    ENTRY = "extern \"C\" void app_main(void) {\n    bareruby_startup();\n    bareruby_main();\n" \
            "    for (;;) {\n        bareruby_sleep_ms(1000, true);\n    }\n}\n"

    def initialize(target, sources:, units: [], debug: false, exceptions: true)
      @target = target
      @sources = sources
      @units = units
      @debug = debug
      @exceptions = exceptions
      @machine = EspIdfBinding.machine(target.machine)
    end

    def files
      { "manifest.txt" => manifest, "CMakeLists.txt" => cmake_lists,
        "#{COMPONENT}/CMakeLists.txt" => component, "sdkconfig.defaults" => sdkconfig }
    end

    # The board's console is a bridge chip of its own, always attached and always
    # listening, so output has somewhere to arrive in every build rather than only in one
    # that paid for a USB stack.
    def stdout? = true

    def entry = ENTRY

    # **Everything the flashing side needs, said here.** A board takes three images at
    # three offsets, and which three is decided by this build rather than by whoever
    # writes them — so the offsets are recorded, the toolchain merges what it finds at
    # them into one image, and flashing is one file at one offset.
    def manifest
      <<~MANIFEST
        target = #{@target.name}
        board = #{@target.machine.key}
        triple = #{@target.isa.triple}
        chip = #{@target.machine.chip}
        idf_target = #{@machine.idf_target}
        toolchain = xtensa-esp-elf-g++
        language_standard = esp-idf setting
        compile_options = esp-idf setting
        sources = #{@sources.join(' ')}
        definitions = #{definitions.join(' ')}
        stdout_channel = uart0
        flash_size = #{@machine.flash_size}
        debug = #{@debug ? 'enabled' : 'disabled'}
        exceptions = #{@exceptions ? 'enabled' : 'disabled'}
        artifact = bareruby_program.bin
        build_command = cmake -B build -S . -G Ninja && cmake --build build
      MANIFEST
    end

    # **Which pin a peripheral came out on is the board's answer**, and it arrives as a
    # definition rather than as a number written into a unit — so one unit serves every
    # board this binding reaches and a second board is a file in machine/ and nothing else.
    def definitions
      @machine.definitions.map { |name, value| "#{name}=#{value}" }
    end

    # Nothing here names the chip. `CONFIG_IDF_TARGET` in the defaults beside this file
    # says which board this is, and the SDK reads it before it decides anything — so the
    # answer is in one place rather than in a cmake line and a configuration that have to
    # agree.
    def cmake_lists
      <<~CMAKE
        cmake_minimum_required(VERSION 3.16)

        include($ENV{IDF_PATH}/tools/cmake/project.cmake)

        project(bareruby_program)
      CMAKE
    end

    # **What the first stage declares everywhere — these are the translation units this
    # program reached for — is what a component registration says here.** The sources are
    # named from the target's own directory and this file sits one level inside it, so
    # every path gains one `..`; the two include directories are the target's directory,
    # where the generated header is, and the root above it, where the runtime is.
    def component
      <<~CMAKE
        idf_component_register(
            SRCS#{sources_text}
            INCLUDE_DIRS ".." "../.."
            REQUIRES #{required.join(' ')})

        target_compile_definitions(${COMPONENT_LIB} PRIVATE#{definitions_text})
      CMAKE
    end

    # **Which of the SDK's components a build compiles at all is decided by what the
    # program reached for.** ESP-IDF ships each driver as a component of its own, and a
    # component nothing requires is never configured, never compiled and never linked —
    # so the split the first stage already made, between the units a program touched and
    # the ones it did not, carries straight through into somebody else's build system.
    # A program that never names a pin does not build a GPIO driver.
    COMPONENTS = {
      gpio: %w[esp_driver_gpio],
      uart: %w[esp_driver_uart esp_driver_gpio],
      uart_receive: %w[esp_driver_uart],
      uart_interrupt: %w[esp_driver_uart],
      pwm: %w[esp_driver_ledc],
      adc: %w[esp_adc],
      i2c: %w[esp_driver_i2c],
      i2c_read: %w[esp_driver_i2c],
      onboard_led: %w[esp_driver_rmt]
    }.freeze

    # The clock every wait is counted on, and the delay every one of them ends in. They
    # are what the unit each build links reaches for, so every build requires them.
    ALWAYS = %w[esp_timer esp_rom freertos].freeze

    def required
      (ALWAYS + @units.flat_map { |unit| COMPONENTS.fetch(unit, []) }).uniq.sort
    end

    def sources_text
      @sources.map { |source| "\n        \"../#{source}\"" }.join
    end

    def definitions_text
      definitions.map { |definition| "\n    #{definition}" }.join
    end

    # What the SDK is configured with, which is where every answer this build makes that is
    # not a source file ends up. The target is here rather than on a cmake line because the
    # SDK reads this first and refuses a build whose two answers disagree.
    #
    # A millisecond tick is what a language with `sleep 0.001` in it needs underneath;
    # FreeRTOS ships at ten milliseconds, which would make every short wait a long one.
    def sdkconfig
      <<~CONFIG
        CONFIG_IDF_TARGET="#{@machine.idf_target}"
        CONFIG_ESPTOOLPY_FLASHSIZE_#{@machine.flash_size}=y
        CONFIG_ESPTOOLPY_FLASHSIZE="#{@machine.flash_size}"
        CONFIG_ESP_CONSOLE_UART_DEFAULT=y
        CONFIG_FREERTOS_HZ=1000
        CONFIG_COMPILER_OPTIMIZATION_#{@debug ? 'DEBUG' : 'SIZE'}=y
        CONFIG_COMPILER_CXX_EXCEPTIONS=#{@exceptions ? 'y' : 'n'}
      CONFIG
    end
  end
end
