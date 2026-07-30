# frozen_string_literal: true

module BareRubyProt
  module Pass
    class TypedConstantFolder
      # Folding never changes a type. Signed add, subtract and
      # multiply are undefined on overflow, so a result outside the type is left alone
      # rather than invented; the defined operations always fold.
      SIGNED_RANGES = {
        int32: (-(2**31)..(2**31 - 1)),
        int64: (-(2**63)..(2**63 - 1))
      }.freeze
      UNDEFINED_ON_OVERFLOW = %w[+ - *].freeze

      attr_reader :result

      def initialize(typed_ast)
        @tast = typed_ast
      end

      def run
        @result = @tast.replace_program(@tast.program_body.map { |statement| fold_node(statement) })

        self
      end

      def fold_node(node)
        case @tast.node_type(node)
        when :class_definition then fold_class_definition(node)
        when :method_definition then fold_method_definition(node)
        when :assignment then fold_assignment(node)
        when :return then fold_return(node)
        when :call then fold_call(node)
        when :interrupt then fold_interrupt(node)
        when :if then fold_if(node)
        when :while then fold_while(node)
        when :begin
          body, rescue_body = @tast.children_of(node)
          @tast.create_begin(fold_body(body), fold_body(rescue_body), span_of(node))
        when :while_true then fold_while_true(node)
        when :for_range then fold_for_range(node)
        when :logical then fold_logical(node)
        when :arena then fold_arena(node)
        when :arena_alloc then fold_arena_alloc(node)
        when :arena_length then fold_arena_length(node)
        when :arena_dup then fold_arena_dup(node)
        when :arena_push then fold_arena_push(node)
        when :arena_index_assign then fold_arena_index_assign(node)
        when :array then fold_array(node)
        when :array_fill then fold_array_fill(node)
        when :array_dup then fold_array_dup(node)
        when :index then fold_index(node)
        when :index_assign then fold_index_assign(node)
        else node
        end
      end

      def fold_arena(node)
        size, body = @tast.children_of(node)
        @tast.create_arena(size, fold_body(body), span_of(node))
      end

      def fold_arena_alloc(node)
        length, initial, type = @tast.children_of(node)
        @tast.create_arena_alloc(fold_node(length), initial && fold_node(initial), type, span_of(node))
      end

      def fold_arena_length(node)
        receiver, type = @tast.children_of(node)
        @tast.create_arena_length(fold_node(receiver), type, span_of(node))
      end

      def fold_arena_dup(node)
        receiver, type = @tast.children_of(node)
        @tast.create_arena_dup(fold_node(receiver), type, span_of(node))
      end

      def fold_arena_push(node)
        receiver, value, type = @tast.children_of(node)
        @tast.create_arena_push(fold_node(receiver), fold_node(value), type, span_of(node))
      end

      def fold_arena_index_assign(node)
        receiver, index, value, type = @tast.children_of(node)
        @tast.create_arena_index_assign(
          fold_node(receiver), fold_node(index), fold_node(value), type, span_of(node)
        )
      end

      def fold_array(node)
        elements, type = @tast.children_of(node)
        @tast.create_array(elements.map { |element| fold_node(element) }, type, span_of(node))
      end

      def fold_array_fill(node)
        value, type = @tast.children_of(node)
        @tast.create_array_fill(value && fold_node(value), type, span_of(node))
      end

      def fold_array_dup(node)
        receiver, type = @tast.children_of(node)
        @tast.create_array_dup(fold_node(receiver), type, span_of(node))
      end

      def fold_index(node)
        receiver, index, type = @tast.children_of(node)
        @tast.create_index(fold_node(receiver), fold_node(index), type, span_of(node))
      end

      def fold_index_assign(node)
        receiver, index, value, type = @tast.children_of(node)
        @tast.create_index_assign(
          fold_node(receiver), fold_node(index), fold_node(value), type, span_of(node)
        )
      end

      def fold_class_definition(node)
        name, ivars, methods = @tast.children_of(node)
        @tast.create_class_definition(name, ivars, methods.map { |method| fold_node(method) }, span_of(node))
      end

      def fold_method_definition(node)
        identity, parameters, body = @tast.children_of(node)
        @tast.create_method_definition(identity, parameters, fold_body(body), span_of(node))
      end

      def fold_assignment(node)
        binding, value, type = @tast.children_of(node)
        @tast.create_assignment(binding, fold_node(value), type, span_of(node))
      end

      def fold_return(node)
        value, type = @tast.children_of(node)
        @tast.create_return(value && fold_node(value), type, span_of(node))
      end

      def fold_if(node)
        condition, then_body, else_body, type = @tast.children_of(node)
        @tast.create_if(
          fold_node(condition), fold_body(then_body), else_body && fold_body(else_body), type, span_of(node)
        )
      end

      def fold_while(node)
        condition, body = @tast.children_of(node)
        @tast.create_while(fold_node(condition), fold_body(body), span_of(node))
      end

      def fold_while_true(node)
        @tast.create_while_true(fold_body(@tast.children_of(node)[0]), span_of(node))
      end

      def fold_for_range(node)
        binding, type, start_value, limit_value, inclusive, body = @tast.children_of(node)
        @tast.create_for_range(
          binding, type, fold_node(start_value), fold_node(limit_value), inclusive, fold_body(body), span_of(node)
        )
      end

      def fold_logical(node)
        operator, left, right, type = @tast.children_of(node)
        @tast.create_logical(operator, fold_node(left), fold_node(right), type, span_of(node))
      end

      def fold_call(node)
        receiver, callee, arguments, block, type = @tast.children_of(node)
        folded_receiver = receiver && fold_node(receiver)
        folded_arguments = arguments.map { |argument| fold_node(argument) }

        if callee[:kind] == :builtin_operator
          value = evaluate(callee[:name], folded_receiver, folded_arguments, type)
          return @tast.create_integer(value, type, span_of(node)) unless value.nil?
        end

        @tast.create_call(folded_receiver, callee, folded_arguments, block, type, span_of(node))
      end

      def fold_interrupt(node)
        receiver, events, block, type = @tast.children_of(node)
        parameters, body, block_type = @tast.children_of(block)
        @tast.create_interrupt(
          fold_node(receiver), fold_node(events),
          @tast.create_block(parameters, fold_body(body), block_type, span_of(block)), type, span_of(node)
        )
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

      def integer?(node) = node && @tast.node_type(node) == :integer

      def value_of(node) = @tast.children_of(node)[0]

      def storage_of(type) = type == :Int64 ? :int64 : (type == :Int32 ? :int32 : nil)

      def span_of(node) = @tast.span_of(node)
    end
  end
end
