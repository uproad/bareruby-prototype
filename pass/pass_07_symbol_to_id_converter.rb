# frozen_string_literal: true

module BareRubyProt
  module Pass
    class SymbolToIdConverter
      attr_reader :result

      def initialize(typed_ir)
        @tir = typed_ir
        @identifiers = {}
      end

      # Symbols become unique integers at compile time and leave no runtime
      # representation behind. Ids follow first appearance in
      # the traversal, which is fixed for a given input.
      def run
        @result = @tir.replace_program(@tir.program_body.map { |statement| convert(statement) })

        self
      end

      def convert(value)
        return value.map { |element| convert(element) } if value.is_a?(Array)
        return :Int32 if value == :Symbol
        return convert_hash(value) if value.is_a?(Hash)

        value
      end

      def convert_hash(value)
        return convert_node(value) if value.key?(:children)

        value.transform_values { |element| convert(element) }
      end

      def convert_node(node)
        return convert_symbol(node) if @tir.node_type(node) == :symbol

        { type: node[:type], children: convert(node[:children]), span: node[:span] }
      end

      def convert_symbol(node)
        name = @tir.children_of(node)[0]
        @identifiers[name] = @identifiers.size unless @identifiers.key?(name)
        @tir.create_integer(@identifiers.fetch(name), :Int32, @tir.span_of(node))
      end
    end
  end
end
