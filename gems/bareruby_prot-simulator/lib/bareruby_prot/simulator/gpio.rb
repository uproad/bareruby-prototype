# frozen_string_literal: true

module BareRubyProt
  module Simulator
    # One pin. What a program set it up as, what it is at right now, and how often that
    # has changed — which is what makes a blink visible from outside without watching
    # every instruction go by.
    #
    # **A pin that is pulled up starts high**, because that is what a pulled-up pin with
    # nothing attached actually reads. The stub the host build links instead answers zero
    # for every pin, which is one of the places a board made of objects and a trace on
    # `fd2` are bound to disagree.
    class Gpio
      IN = 1
      OUT = 2
      HIGH_Z = 4
      PULL_UP = 8
      PULL_DOWN = 16
      OPEN_DRAIN = 32

      # The one edge a program can ask to be notified about.
      EDGE_FALL = 4

      attr_reader :pin, :params, :level, :changes, :events, :handler

      def initialize(pin, params)
        @pin = pin
        @params = params
        @level = params.anybits?(PULL_UP) ? 1 : 0
        @changes = 0
        @events = 0
        @handler = nil
      end

      def direction
        return :high_z if @params.anybits?(HIGH_Z)

        @params.anybits?(OUT) ? :out : :in
      end

      def pull
        return :up if @params.anybits?(PULL_UP)
        return :down if @params.anybits?(PULL_DOWN)

        :none
      end

      def open_drain? = @params.anybits?(OPEN_DRAIN)

      def high? = @level == 1

      def low? = @level.zero?

      def level=(value)
        settled = value.zero? ? 0 : 1
        @changes += 1 unless settled == @level
        @level = settled
      end

      def watch(events, handler)
        @events = events
        @handler = handler
      end

      # Whether moving to this level is the edge somebody asked to hear about.
      def edge?(level) = @handler && @events.anybits?(EDGE_FALL) && level.zero? && high?
    end
  end
end
