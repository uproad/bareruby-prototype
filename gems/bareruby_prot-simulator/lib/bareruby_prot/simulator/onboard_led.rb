# frozen_string_literal: true

module BareRubyProt
  module Simulator
    # The indicator the board carries. Where it is and how it is driven belong to the
    # board rather than to the program, so there is nothing here but whether it is lit.
    class OnboardLed
      attr_reader :level, :changes

      def initialize
        @level = 0
        @changes = 0
      end

      # What the indicator is, as plain data.
      def snapshot = { level: @level, changes: @changes }

      def on? = @level == 1

      def level=(value)
        settled = value.zero? ? 0 : 1
        @changes += 1 unless settled == @level
        @level = settled
      end
    end
  end
end
