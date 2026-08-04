# frozen_string_literal: true

require_relative "binding"

module BareRubyProt
  # How the second stage builds a program for a board reached through the Arduino core.
  # The core owns reset, the clock, the timers and main; this side contributes translation
  # units and the two functions the core calls.
  #
  # What the second stage takes is not a build file but a directory: arduino-cli reads a
  # sketch whole. So the first stage declares which translation units the program reached
  # for, as it does everywhere else, and the toolchain gathers exactly those into one.
  class ArduinoBuild
    SKETCH = "bareruby_program"

    # The core calls setup once and loop forever, so a program is entered from setup and
    # never comes back — its own loop is the program. A board has nowhere to return to,
    # and here that is not this side's arrangement but the core's, already made. The two
    # are C symbols, because that is how the core's main calls them.
    ENTRY = "extern \"C\" void setup(void) {\n    bareruby_startup();\n    bareruby_main();\n}\n\n" \
            "extern \"C\" void loop(void) {\n}\n"

    # A directory is a sketch only if it holds a file of its own name, so there has to be
    # one and there is nothing for it to hold: setup and loop are in the program beside
    # it, which the toolchain copies in with everything else this program reached for.
    SKETCH_TEXT = "// The program is in #{ArduinoBinding::PROGRAM_FILE}, beside this file.\n"

    def initialize(target, sources:, units: [], debug: false, exceptions: true)
      @target = target
      @sources = sources
    end

    def files = {
      "manifest.txt" => manifest,
      "#{SKETCH}/#{SKETCH}.ino" => SKETCH_TEXT
    }

    # The board's console is a bridge chip of its own, always attached and always
    # listening, so output has somewhere to arrive in every build rather than only in one
    # that paid for a USB stack.
    def stdout? = true

    def entry = ENTRY

    def fqbn = ArduinoBinding.machine(@target.machine).fqbn

    def manifest
      <<~MANIFEST
        target = #{@target.name}
        board = #{@target.machine.key}
        triple = #{@target.isa.triple}
        chip = #{@target.machine.chip}
        fqbn = #{fqbn}
        toolchain = arduino-cli
        language_standard = arduino core setting
        compile_options = arduino core setting
        sketch = #{SKETCH}
        sources = #{@sources.join(' ')}
        stdout_channel = serial
        exceptions = unavailable (this core compiles with -fno-exceptions)
        artifact = bareruby_program.hex
        build_command = arduino-cli compile --fqbn #{fqbn} --build-path build --output-dir . #{SKETCH}
      MANIFEST
    end
  end
end
