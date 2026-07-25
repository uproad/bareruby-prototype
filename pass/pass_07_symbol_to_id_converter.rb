# frozen_string_literal: true

module BareRubyProt
  module Pass
    class SymbolToIdConverter
      attr_reader :result

      def initialize(typed_ir)
        @tir = typed_ir
      end

      def run
        @result = @tir

        self
      end
    end
  end
end
