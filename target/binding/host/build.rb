# frozen_string_literal: true

module BareRubyProt
  # How the second stage builds a program for the machine doing the compiling: one g++
  # invocation, and the record of it that says what that invocation was.
  class HostBuild
    # The compiling machine has a terminal, so output always reaches somewhere, and the
    # program ends rather than idling: falling off the end of it is the run finishing.
    ENTRY = "int main(void) {\n    bareruby_main();\n    return 0;\n}\n"

    # Every build is asked for in the same words, and answers with what it needs of them.
    def initialize(target, sources:, units: [], debug: false, exceptions: true)
      @target = target
      @sources = sources.join(" ")
    end

    def files = { "manifest.txt" => manifest }

    def stdout? = true

    def entry = ENTRY

    def manifest
      <<~MANIFEST
        target = #{@target.name}
        triple = #{@target.isa.triple}
        toolchain = g++
        language_standard = gnu++20
        compile_options = -std=gnu++20 -fno-rtti
        include_directories = ..
        sources = #{@sources}
        link_libraries =
        stdout_channel = printf
        exceptions = enabled
        artifact = bareruby_program
        build_command = g++ -std=gnu++20 -fno-rtti -I.. -o bareruby_program #{@sources}
      MANIFEST
    end
  end
end
