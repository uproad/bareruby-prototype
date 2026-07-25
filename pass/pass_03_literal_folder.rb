# frozen_string_literal: true

module BareRubyProt
  module Pass
    class LiteralFolder
      BINARY_OPERATORS = %i[+ - * / % << >> & | ^].freeze
      UNARY_OPERATORS = %i[-@ ~].freeze

      attr_reader :result

      def initialize(bareruby_ast)
        @bareruby_ast = bareruby_ast
      end

      def run
        body = @bareruby_ast.program_body.map { |statement| preevaluate_node(statement) }
        @result = @bareruby_ast.replace_program(body, @bareruby_ast.program_span)

        self
      end

      def preevaluate_node(node)
        case @bareruby_ast.node_type(node)
        when :integer, :float, :boolean, :string, :symbol, :reference, :constant_path, :parameter, :iteration_control
          node
        when :if
          preevaluate_if(node)
        when :while
          preevaluate_while(node)
        when :logical
          preevaluate_logical(node)
        when :keyword_argument
          name, value = @bareruby_ast.children_of(node)
          @bareruby_ast.create_keyword_argument(name, preevaluate_node(value), span_of(node))
        when :interpolation
          @bareruby_ast.create_interpolation(
            @bareruby_ast.children_of(node)[0].map { |part| preevaluate_node(part) }, span_of(node)
          )
        when :assignment
          preevaluate_assignment(node)
        when :method_definition
          preevaluate_method_definition(node)
        when :class_definition
          preevaluate_class_definition(node)
        when :call
          preevaluate_call(node)
        when :block
          preevaluate_block(node)
        when :return
          preevaluate_return(node)
        end
      end

      def preevaluate_assignment(node)
        target, value = @bareruby_ast.children_of(node)
        @bareruby_ast.create_assignment(target, preevaluate_node(value), span_of(node))
      end

      def preevaluate_method_definition(node)
        name, parameters, body = @bareruby_ast.children_of(node)
        @bareruby_ast.create_method_definition(name, parameters, preevaluate_body(body), span_of(node))
      end

      def preevaluate_class_definition(node)
        name, body = @bareruby_ast.children_of(node)
        @bareruby_ast.create_class_definition(name, preevaluate_body(body), span_of(node))
      end

      def preevaluate_call(node)
        value = evaluate_constant(node)
        return @bareruby_ast.create_integer(value, span_of(node)) if value

        receiver, name, arguments, block = @bareruby_ast.children_of(node)
        @bareruby_ast.create_call(
          receiver && preevaluate_node(receiver),
          name,
          arguments.map { |argument| preevaluate_node(argument) },
          block && preevaluate_node(block),
          span_of(node)
        )
      end

      def preevaluate_block(node)
        parameters, body = @bareruby_ast.children_of(node)
        @bareruby_ast.create_block(parameters, preevaluate_body(body), span_of(node))
      end

      def preevaluate_return(node)
        value = @bareruby_ast.children_of(node)[0]
        @bareruby_ast.create_return(value && preevaluate_node(value), span_of(node))
      end

      def preevaluate_if(node)
        condition, then_body, else_body = @bareruby_ast.children_of(node)
        @bareruby_ast.create_if(
          preevaluate_node(condition),
          preevaluate_body(then_body),
          else_body && preevaluate_body(else_body),
          span_of(node)
        )
      end

      def preevaluate_while(node)
        condition, body = @bareruby_ast.children_of(node)
        @bareruby_ast.create_while(preevaluate_node(condition), preevaluate_body(body), span_of(node))
      end

      def preevaluate_logical(node)
        operator, left, right = @bareruby_ast.children_of(node)
        @bareruby_ast.create_logical(operator, preevaluate_node(left), preevaluate_node(right), span_of(node))
      end

      def preevaluate_body(statements)
        statements.map { |statement| preevaluate_node(statement) }
      end

      def evaluate_constant(node)
        case @bareruby_ast.node_type(node)
        when :integer
          @bareruby_ast.children_of(node)[0]
        when :call
          evaluate_constant_call(node)
        end
      end

      def evaluate_constant_call(node)
        receiver, name, arguments, block = @bareruby_ast.children_of(node)
        return if block || receiver.nil?

        receiver_value = evaluate_constant(receiver)
        return unless receiver_value

        if arguments.empty? && UNARY_OPERATORS.include?(name)
          apply_unary(name, receiver_value)
        elsif arguments.length == 1 && BINARY_OPERATORS.include?(name)
          argument_value = evaluate_constant(arguments[0])
          apply_binary(name, receiver_value, argument_value) if argument_value
        end
      end

      def apply_unary(operator, value)
        case operator
        when :-@ then -value
        when :~ then ~value
        end
      end

      def apply_binary(operator, left, right)
        case operator
        when :+ then left + right
        when :- then left - right
        when :* then left * right
        when :/ then truncate_divide(left, right)
        when :% then left - (truncate_divide(left, right) * right)
        when :<< then left << right
        when :>> then left >> right
        when :& then left & right
        when :| then left | right
        when :^ then left ^ right
        end
      end

      def truncate_divide(left, right)
        quotient = left.abs / right.abs
        left.negative? ^ right.negative? ? -quotient : quotient
      end

      def span_of(node) = @bareruby_ast.span_of(node)
    end
  end
end
