# frozen_string_literal: true

require_relative "../toolchain"

module BareRubyProt
  # One g++ invocation, which the manifest already spells out in full. The compiling
  # machine needs nothing found or configured first, so there is nothing here but running
  # what was written down.
  module HostToolchain
    ARTIFACT = "bareruby_program"

    def self.run(directory, options: {})
      Toolchain.run(directory, Toolchain.recorded_command(directory))
    end

    def self.artifact(directory) = File.join(directory, ARTIFACT)
  end
end
