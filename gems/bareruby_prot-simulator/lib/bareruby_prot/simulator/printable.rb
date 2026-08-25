# frozen_string_literal: true

module BareRubyProt
  module Simulator
    # Bytes as something that can be read. What a port carries is bytes, and not every
    # byte is a character — so what is not a printable one is spelled the way C spells it,
    # and what comes out can be handed to anything that reads text.
    module Printable
      def printable(bytes)
        bytes.b.gsub(/[^\x20-\x7e]/) { |byte| format("\\x%02x", byte.ord) }
      end
    end
  end
end
