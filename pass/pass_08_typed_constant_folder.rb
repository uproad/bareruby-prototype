# frozen_string_literal: true

module BareRubyProt
  module Pass
    class TypedConstantFolder
      # Folding never changes a type (LANGUAGE.md section 5.4). Signed add, subtract and
      # multiply are undefined on overflow, so a result outside the type is left alone
      # rather than invented; the defined operations always fold.
      SIGNED_RANGES = {
        int32: (-(2**31)..(2**31 - 1)),
        int64: (-(2**63)..(2**63 - 1))
      }.freeze
      UNDEFINED_ON_OVERFLOW = %w[+ - *].freeze

      attr_reader :result

      def initialize(typed_ir)
        @tir = typed_ir
      end

      def run
        @result = @tir.replace_program(@tir.program_body.map { |statement| fold_node(statement) })

        self
      end

      def fold_node(node)
        case @tir.node_type(node)
        when :class_definition then fold_class_definition(node)
        when :method_definition then fold_method_definition(node)
        when :assignment then fold_assignment(node)
        when :return then fold_return(node)
        when :call then fold_call(node)
        when :if then fold_if(node)
        when :while then fold_while(node)
        when :while_true then fold_while_true(node)
        when :for_range then fold_for_range(node)
        when :logical then fold_logical(node)
        else node
        end
      end

      def fold_class_definition(node)
        name, ivars, methods = @tir.children_of(node)
        @tir.create_class_definition(name, ivars, methods.map { |method| fold_node(method) }, span_of(node))
      end

      def fold_method_definition(node)
        identity, parameters, body = @tir.children_of(node)
        @tir.create_method_definition(identity, parameters, fold_body(body), span_of(node))
      end

      def fold_assignment(node)
        binding, value, type = @tir.children_of(node)
        @tir.create_assignment(binding, fold_node(value), type, span_of(node))
      end

      def fold_return(node)
        value, type = @tir.children_of(node)
        @tir.create_return(value && fold_node(value), type, span_of(node))
      end

      def fold_if(node)
        condition, then_body, else_body, type = @tir.children_of(node)
        @tir.create_if(
          fold_node(condition), fold_body(then_body), else_body && fold_body(else_body), type, span_of(node)
        )
      end

      def fold_while(node)
        condition, body = @tir.children_of(node)
        @tir.create_while(fold_node(condition), fold_body(body), span_of(node))
      end

      def fold_while_true(node)
        @tir.create_while_true(fold_body(@tir.children_of(node)[0]), span_of(node))
      end

      def fold_for_range(node)
        binding, type, start_value, limit_value, inclusive, body = @tir.children_of(node)
        @tir.create_for_range(
          binding, type, fold_node(start_value), fold_node(limit_value), inclusive, fold_body(body), span_of(node)
        )
      end

      def fold_logical(node)
        operator, left, right, type = @tir.children_of(node)
        @tir.create_logical(operator, fold_node(left), fold_node(right), type, span_of(node))
      end

      def fold_call(node)
        receiver, callee, arguments, block, type = @tir.children_of(node)
        folded_receiver = receiver && fold_node(receiver)
        folded_arguments = arguments.map { |argument| fold_node(argument) }

        if callee[:kind] == :builtin_operator
          value = evaluate(callee[:name], folded_receiver, folded_arguments, type)
          return @tir.create_integer(value, type, span_of(node)) unless value.nil?
        end

        @tir.create_call(folded_receiver, callee, folded_arguments, block, type, span_of(node))
      end

      def fold_body(statements) = statements.map { |statement| fold_node(statement) }

      def evaluate(operator, receiver, arguments, type)
        return unless SIGNED_RANGES.key?(storage_of(type))
        return unless integer?(receiver) && arguments.all? { |argument| integer?(argument) }

        value = apply(operator.to_s, value_of(receiver), arguments.map { |argument| value_of(argument) })
        return if value.nil?
        return if UNDEFINED_ON_OVERFLOW.include?(operator.to_s) && !SIGNED_RANGES.fetch(storage_of(type)).cover?(value)

        value
      end

      def apply(operator, receiver, arguments)
        return apply_unary(operator, receiver) if arguments.empty?

        apply_binary(operator, receiver, arguments.first)
      end

      def apply_unary(operator, value)
        case operator
        when "-@" then -value
        when "~" then ~value
        end
      end

      def apply_binary(operator, left, right)
        case operator
        when "+" then left + right
        when "-" then left - right
        when "*" then left * right
        when "&" then left & right
        when "|" then left | right
        when "^" then left ^ right
        when "<<" then left << right
        when ">>" then left >> right
        end
      end

      def integer?(node) = node && @tir.node_type(node) == :integer

      def value_of(node) = @tir.children_of(node)[0]

      def storage_of(type) = type == :Int64 ? :int64 : (type == :Int32 ? :int32 : nil)

      def span_of(node) = @tir.span_of(node)
    end
  end
end
