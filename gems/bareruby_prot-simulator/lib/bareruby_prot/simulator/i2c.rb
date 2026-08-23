# frozen_string_literal: true

module BareRubyProt
  module Simulator
    # One two-wire bus. There is no device on it, so a read answers whatever was put here
    # to be answered with — a test saying what the sensor replies, or the wire a run was
    # started with. Every write is kept, addressed, because what a program sent a device
    # is the whole of what a bus with no device on it can be checked against.
    class I2c
      Transfer = Data.define(:address, :bytes)

      attr_reader :unit, :frequency, :written
      attr_accessor :wire

      def initialize(unit, frequency)
        @unit = unit
        @frequency = frequency
        @written = []
        @answers = +""
        @wire = nil
      end

      # What the next reads take their bytes from.
      def answer_with(bytes) = @answers << bytes

      def write(address, bytes)
        @written << Transfer.new(address: address, bytes: bytes)
        bytes.bytesize
      end

      def read(address, length, outputs)
        @written << Transfer.new(address: address, bytes: outputs) unless outputs.empty?
        taken(length)
      end

      private

      def taken(length)
        @answers << (@wire&.read(length - @answers.bytesize) || "") if @answers.bytesize < length
        @answers.slice!(0, length)
      end
    end
  end
end
