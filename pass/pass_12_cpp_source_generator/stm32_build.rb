# frozen_string_literal: true

module BareRubyProt
  # The CubeIDE project owns reset, clocks, peripheral initialization, the linker script,
  # and the final link. BareRuby contributes C++ translation units entered from main.c
  # after CubeMX has initialized every configured peripheral.
  class Stm32Build
    ENTRY = <<~CPP
      extern "C" void bareruby_entry(void) {
          bareruby_startup();
          bareruby_main();
      }
    CPP

    def initialize(target, sources:, exceptions:)
      @target = target
      @sources = sources
      @exceptions = exceptions
    end

    def files = {
      "manifest.txt" => manifest,
      "source-list.txt" => source_list
    }

    # USART2 is the board's configured stdout channel. Its _write bridge is supplied by
    # the STM32 binding, so global puts calls remain observable in this build.
    def stdout? = true

    def entry = ENTRY

    # The CubeIDE bridge consumes this list instead of copying every generated unit.
    # Keeping the selection made by pass 12 preserves the feature-based link boundary:
    # an application that does not receive over UART or use I2C does not compile those
    # bindings into its firmware.
    def source_list = "#{@sources.join("\n")}\n"

    def manifest
      <<~MANIFEST
        target = #{@target.name}
        board = #{@target.board}
        platform = #{@target.platform}
        toolchain = STM32CubeIDE MCU ARM GCC
        language_standard = CubeIDE project setting
        compile_options = CubeIDE project setting
        cube_project = user-supplied CubeIDE project
        generated_sources = #{@sources.join(' ')}
        stdout_channel = USART2
        exceptions = #{@exceptions ? 'enabled' : 'disabled'}
        artifact = CubeIDE configuration output
      MANIFEST
    end
  end
end
