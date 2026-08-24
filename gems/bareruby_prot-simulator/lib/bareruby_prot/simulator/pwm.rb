# frozen_string_literal: true

module BareRubyProt
  module Simulator
    # One pin driven as a square wave: what it was last told, in each of the two pairs of
    # words a program is allowed to say it in. A period and a frequency are the same
    # setting asked for two ways, and so are a pulse width and a duty cycle, so both
    # spellings are kept — reading back the one that was not used is how a display says
    # what the pin is actually doing.
    class Pwm
      attr_reader :pin, :slice, :frequency, :duty

      def initialize(pin, frequency, duty)
        @pin = pin
        @slice = pin / 2
        @frequency = frequency
        @duty = duty
      end

      # What this pin is being driven as, as plain data. Both spellings of each pair are
      # here, because reading back the one that was not used is the point of keeping them.
      def snapshot
        { pin: @pin, slice: @slice, frequency: @frequency, duty: @duty,
          period_us: period_us, pulse_width_us: pulse_width_us }
      end

      def frequency=(hertz)
        @frequency = hertz
      end

      def period_us=(microseconds)
        @frequency = 1_000_000 / microseconds
      end

      def duty=(percent)
        @duty = percent
      end

      def pulse_width_us=(microseconds)
        @duty = microseconds * @frequency / 10_000
      end

      def period_us = @frequency.zero? ? 0 : 1_000_000 / @frequency

      def pulse_width_us = period_us * @duty / 100
    end
  end
end
