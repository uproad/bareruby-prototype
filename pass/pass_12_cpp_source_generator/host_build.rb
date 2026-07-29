# frozen_string_literal: true

module BareRubyProt
  # How the second stage builds a program for the machine doing the compiling: one g++
  # invocation, and the record of it that says what that invocation was.
  class HostBuild
    def initialize(sources:)
      @sources = sources.join(" ")
    end

    def files = { "manifest.txt" => manifest }

    def manifest
      <<~MANIFEST
        target = host
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
