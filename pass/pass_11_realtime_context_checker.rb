# frozen_string_literal: true

module BareRubyProt
  module Pass
    class RealtimeContextChecker
      attr_reader :result

      def initialize(low_ir)
        @lir = low_ir
      end

      def run
        functions = @lir.functions.to_h { |function| [@lir.children_of(function)[0], function] }
        roots = functions.values.select { |function| @lir.children_of(function)[4] == :realtime }
        roots.each { |function| check_function(function, functions, {}) }
        @result = @lir
        self
      end

      def check_function(function, functions, seen)
        name, _parameters, _return_type, body, = @lir.children_of(function)
        return if seen[name]

        seen[name] = true
        raise "realtime handler reaches an arena operation in #{name}" if arena_operation?(body)

        calls_in(body).each do |callee|
          target = functions[callee]
          check_function(target, functions, seen) if target
        end
      end

      def arena_operation?(value)
        return value.any? { |element| arena_operation?(element) } if value.is_a?(Array)
        return false unless value.is_a?(Hash)
        return true if value[:type] == :declare_arena_storage
        return true if value[:type] == :call && value[:children][0] == :bareruby_arena_alloc

        arena_operation?(value[:children])
      end

      def calls_in(value)
        return value.flat_map { |element| calls_in(element) } if value.is_a?(Array)
        return [] unless value.is_a?(Hash)

        calls = value[:type] == :call ? [value[:children][0]] : []
        calls + calls_in(value[:children])
      end
    end
  end
end
