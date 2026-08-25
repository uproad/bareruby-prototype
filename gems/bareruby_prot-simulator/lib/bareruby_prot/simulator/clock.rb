# frozen_string_literal: true

module BareRubyProt
  module Simulator
    # Time, as far as the program is concerned. Nothing here reads the desk's clock: a
    # wait moves this forward by exactly what it was asked to wait for, so two runs of one
    # program see the same milliseconds go by, on any machine, at any speed.
    #
    # **That is what makes a run repeatable.** A program that watches the clock takes the
    # same branch every time, and what a board did at 500 ms is a fact rather than a race.
    class Clock
      MILLISECOND = 1000

      SECOND = 1_000_000

      # What one instruction costs. **A program that never waits still has to end**, and
      # this is what ends it: a loop with nothing in it but pin writes runs out of the
      # time the run was given rather than running for as long as somebody is patient.
      #
      # One microsecond makes this a one-megahertz machine, which is slower than any
      # board these programs are written for. It is a choice rather than a measurement —
      # what matters is that it is the same on every desk, so that a run that ends after
      # so many instructions here ends after exactly as many everywhere.
      INSTRUCTION = 1

      attr_reader :microseconds

      def initialize(seconds)
        @microseconds = 0
        @limit = seconds && seconds * SECOND
      end

      def ticks_ms = @microseconds / MILLISECOND

      def advance(microseconds) = @microseconds += microseconds

      # Whether the run has had the time it was given. A firmware loops forever by design,
      # so how long to watch is the one thing a run has to be told — **unless it is not
      # told at all**, and then it is never over. A display watching a loop is watching it
      # because it does not end; that is the thing being looked at.
      def over? = @limit ? @microseconds >= @limit : false

      def seconds = @microseconds.fdiv(SECOND)
    end
  end
end
