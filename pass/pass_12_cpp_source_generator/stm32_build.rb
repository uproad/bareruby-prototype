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

    def files = { "manifest.txt" => manifest }

    # USART2 is the board's configured stdout channel. Its _write bridge is supplied by
    # the STM32 binding, so global puts calls remain observable in this build.
    def stdout? = true

    def entry = ENTRY

    def manifest
      <<~MANIFEST
        target = #{@target.name}
        board = #{@target.board}
        platform = #{@target.platform}
        toolchain = STM32CubeIDE MCU ARM GCC
        language_standard = gnu++20
        compile_options = -std=gnu++20 -fno-rtti#{@exceptions ? '' : ' -fno-exceptions'}
        cube_project = platform/stm32/F446_Sample
        generated_sources = #{@sources.join(' ')}
        stdout_channel = USART2
        exceptions = #{@exceptions ? 'enabled' : 'disabled'}
        artifact = Debug/F446_Sample.elf
      MANIFEST
    end
  end
end
