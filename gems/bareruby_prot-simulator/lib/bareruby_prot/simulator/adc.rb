# frozen_string_literal: true

module BareRubyProt
  module Simulator
    # One analog input. Nothing is attached to it, so what it reads is whatever was put
    # there from outside — a test setting up the reading it wants to see, or a display
    # letting somebody turn a knob. It starts at zero, which is what a floating input on
    # a board with nothing on it reads anyway.
    class Adc
      # What the converter answers at full scale. Twelve bits, which is what the boards
      # these classes were written against carry.
      FULL = 4095

      attr_reader :pin, :channel, :reads
      attr_accessor :raw

      def initialize(pin)
        @pin = pin
        @channel = pin - 26
        @raw = 0
        @reads = 0
      end

      def read
        @reads += 1
        @raw
      end
    end
  end
end
