# frozen_string_literal: true

module BareRubyProt
  module Simulator
    # One serial port: the frame it was opened with, everything it has put on the wire,
    # and the queue of what has arrived on it.
    #
    # **The send side keeps what it sent.** A board writes bytes and they are gone, but
    # the whole point of a port made of objects is that what it said is still there to be
    # read back — by a display showing the line, and by a check comparing it against what
    # the same program said elsewhere.
    #
    # **The receive side is one queue, and whoever asks first takes what is in it.** A
    # handler and a program calling `getbyte` are the same kind of consumer. When nothing
    # has been put there from outside, the queue fills from whatever was attached as the
    # wire — which is how a run started from a shell takes its input on `stdin`.
    class Uart
      # How deep the queue is when the program did not ask for a depth of its own.
      DEPTH = 256

      PARITIES = { 0 => :none, 1 => :even, 2 => :odd }.freeze

      RTSCTS = 4

      KEEP = -1

      attr_reader :unit, :txd_pin, :rxd_pin, :baudrate, :data_bits, :stop_bits,
                  :flow_control, :rts_pin, :cts_pin, :line_ending, :transmitted,
                  :breaks, :events, :handler
      attr_accessor :wire

      def initialize(unit, settings)
        @unit = unit
        @txd_pin, @rxd_pin, @baudrate, @data_bits, @stop_bits, @parity,
          @flow_control, @rts_pin, @cts_pin = settings
        @line_ending = "\n"
        @transmitted = +""
        @received = +""
        @breaks = 0
        @events = 0
        @handler = nil
        @wire = nil
      end

      def parity = PARITIES.fetch(@parity)

      def flow_control? = @flow_control.anybits?(RTSCTS)

      # What `setmode` does: -1 is how it says a field is not being changed, so what
      # arrives is folded into what is already there.
      def settle(settings)
        @baudrate, @data_bits, @stop_bits, @parity, @flow_control, @rts_pin, @cts_pin =
          [@baudrate, @data_bits, @stop_bits, @parity, @flow_control, @rts_pin, @cts_pin]
          .zip(settings).map { |kept, asked| asked == KEEP ? kept : asked }
      end

      # The seven settings `setmode` names, in the order the struct carries them.
      def frame = [@baudrate, @data_bits, @stop_bits, @parity, @flow_control, @rts_pin, @cts_pin]

      def line_ending=(value)
        @line_ending = value
      end

      def transmit(bytes) = @transmitted << bytes

      def break_for(_milliseconds) = @breaks += 1

      def clear_transmitted = @transmitted.clear

      # ---- what has arrived -----------------------------------------------------

      def receive(bytes) = @received << bytes.byteslice(0, DEPTH - @received.bytesize)

      def pending
        fill
        @received.bytesize
      end

      def peek
        fill
        @received.empty? ? nil : @received.getbyte(0)
      end

      def take
        fill
        @received.empty? ? nil : @received.slice!(0).getbyte(0)
      end

      def clear_received
        fill
        @received.clear
      end

      def waiting? = !@received.empty?

      def watch(events, handler)
        @events = events
        @handler = handler
      end

      private

      # What the interrupt does on a board: move whatever the line has delivered into the
      # queue. Reading the wire without blocking is what keeps a wire saying nothing from
      # being the same as a program stopping.
      def fill
        return unless @wire

        arrived = @wire.read_nonblock(DEPTH - @received.bytesize, exception: false)
        receive(arrived) if arrived.is_a?(String)
      end
    end
  end
end
