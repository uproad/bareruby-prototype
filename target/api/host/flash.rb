# frozen_string_literal: true

module BareRubyProt
  # There is nowhere to write to. The artifact is already on the machine that will run it,
  # which is the same machine that compiled it, so flashing a hosted target is finishing
  # immediately rather than being an error.
  module HostFlash
    def self.run(directory, boards:, options: {}) = true
  end
end
