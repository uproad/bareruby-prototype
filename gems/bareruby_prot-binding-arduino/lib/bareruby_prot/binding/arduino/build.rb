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
    # and here that is not this side's arrangement but the core's, already made.
    #
    # **Which linkage the core calls the two with is the core's answer, and the two cores
    # here disagree.** One declares them inside `extern "C"` and calls C symbols; the other
    # declares them as C++ and calls mangled ones. Neither is this side's to choose, and a
    # program written for the wrong one links against nothing.
    BODY = "{\n    bareruby_startup();\n    bareruby_main();\n}\n\n"

    ENTRY = "#ifdef ARDUINO_ARCH_ESP32\nvoid setup(void) #{BODY}void loop(void) {}\n" \
            "#else\nextern \"C\" void setup(void) #{BODY}extern \"C\" void loop(void) {}\n" \
            "#endif\n"

    # A directory is a sketch only if it holds a file of its own name, so there has to be
    # one and there is nothing for it to hold: setup and loop are in the program beside
    # it, which the toolchain copies in with everything else this program reached for.
    SKETCH_TEXT = "// The program is in #{ArduinoBinding::PROGRAM_FILE}, beside this file.\n"

    def initialize(target, sources:, units: [], debug: false, exceptions: true)
      @target = target
      @sources = sources
      @exceptions = exceptions
      @machine = ArduinoBinding.machine(target.machine)
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

    def fqbn = @machine.fqbn

    # **Which pin a peripheral came out on is the board's answer**, and it arrives as a
    # definition rather than as a number written into a unit — so one unit serves every
    # board this binding reaches, and a second board is a file in machine/ and nothing
    # else. The converter's reference and its width come the same way, because a board is
    # what decides them as much as a chip is.
    def definitions
      @machine.definitions.map { |name, value| "-D#{name}=#{value}" }
    end

    # **Where a core can be asked for exceptions, `--no-exceptions` is what asks.** One of
    # these boards compiles with them and one cannot have them at all, so the flag is added
    # only where its absence would have meant something else.
    def flags
      definitions + (@machine.exceptions? && !@exceptions ? ["-fno-exceptions"] : [])
    end

    def exceptions
      return "unavailable (this core compiles with -fno-exceptions)" unless @machine.exceptions?

      @exceptions ? "enabled" : "disabled"
    end

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
        definitions = #{definitions.join(' ')}
        stdout_channel = serial
        exceptions = #{exceptions}
        artifact = #{@machine.artifact}
        build_command = #{build_command}
      MANIFEST
    end

    def build_command
      "arduino-cli compile --fqbn \"#{fqbn}\" " \
        "--build-property \"compiler.cpp.extra_flags=#{flags.join(' ')}\" " \
        "--build-path build --output-dir . #{SKETCH}"
    end
  end
end
