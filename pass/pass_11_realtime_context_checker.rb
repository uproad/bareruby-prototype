# frozen_string_literal: true

module BareRubyProt
  module Pass
    class RealtimeContextChecker
      attr_reader :result

      def initialize(low_ir)
        @lir = low_ir
      end

      def run
        @lir.realtime_reachable_functions.each do |function|
          raise "realtime handler reaches an arena operation in #{@lir.function_name(function)}" if @lir.arena_operation?(function)
        end
        @result = @lir
        self
      end
    end
  end
end
