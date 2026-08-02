# frozen_string_literal: true

module BareRubyProt
  # The manifest cannot spell this second stage out in one line, because the build does
  # not happen here: the generated units are placed into a project this repository does
  # not own, and STM32CubeIDE links them. cube.sh does that, and it is left in the shell
  # it was proved in.
  module Stm32CubeToolchain
    SCRIPT = File.expand_path("cube.sh", __dir__)
    ARTIFACT = "bareruby_program.elf"

    def self.run(directory, options: {})
      system(SCRIPT, directory, options["cube_project"].to_s,
             options["configuration"] || "Debug", exception: true)
    end

    def self.artifact(directory) = File.join(directory, ARTIFACT)
  end
end
