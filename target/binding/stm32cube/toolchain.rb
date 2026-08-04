# frozen_string_literal: true

module BareRubyProt
  # The manifest cannot spell this second stage out in one line, because the build does
  # not happen here: the generated units are placed into a project this repository does
  # not own, and are compiled there against the HAL that project carries. cube.sh does
  # that placing and runs the build, and it is left in the shell it was proved in.
  module Stm32CubeToolchain
    SCRIPT = File.expand_path("cube.sh", __dir__)
    ARTIFACT = "bareruby_program.elf"

    def self.run(directory, options: {})
      system(SCRIPT, directory, options["cube_project"].to_s,
             options["configuration"] || "Debug")
    end

    def self.artifact(directory) = File.join(directory, ARTIFACT)
  end
end
