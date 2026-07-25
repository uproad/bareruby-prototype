# frozen_string_literal: true

module BareRubyProt
  module Pass
    class Desugarer
      attr_reader :result

      def initialize(bareruby_ast)
        @bareruby_ast = bareruby_ast
      end

      def run
        body = @bareruby_ast.program_body.map { |statement| desugar_node(statement) }
        @result = @bareruby_ast.replace_program(body, @bareruby_ast.program_span)

        self
      end

      def desugar_node(node)
        case @bareruby_ast.node_type(node)
        when :integer, :reference, :parameter, :iteration_control
          node
        when :assignment
          desugar_assignment(node)
        when :compound_assignment
          desugar_compound_assignment(node)
        when :method_definition
          desugar_method_definition(node)
        when :subclass_definition
          desugar_subclass_definition(node)
        when :call
          desugar_call(node)
        when :block
          desugar_block(node)
        when :return
          desugar_return(node)
        end
      end

      def desugar_assignment(node)
        target, value = @bareruby_ast.children_of(node)
        @bareruby_ast.create_assignment(target, desugar_node(value), span_of(node))
      end

      def desugar_compound_assignment(node)
        target, operator, value = @bareruby_ast.children_of(node)
        span = span_of(node)
        call = @bareruby_ast.create_call(target, operator, [desugar_node(value)], nil, span)
        @bareruby_ast.create_assignment(target, call, span)
      end

      def desugar_method_definition(node)
        name, parameters, body = @bareruby_ast.children_of(node)
        @bareruby_ast.create_method_definition(name, parameters, desugar_method_body(body), span_of(node))
      end

      def desugar_subclass_definition(node)
        name, superclass, body = @bareruby_ast.children_of(node)
        span = span_of(node)
        include_target = @bareruby_ast.create_reference(:constant, superclass, span)
        include_call = @bareruby_ast.create_call(nil, :include, [include_target], nil, span)
        @bareruby_ast.create_class_definition(name, [include_call] + desugar_body(body), span)
      end

      def desugar_call(node)
        receiver, name, arguments, block = @bareruby_ast.children_of(node)
        @bareruby_ast.create_call(
          receiver && desugar_node(receiver),
          name,
          arguments.map { |argument| desugar_node(argument) },
          block && desugar_node(block),
          span_of(node)
        )
      end

      def desugar_block(node)
        parameters, body = @bareruby_ast.children_of(node)
        @bareruby_ast.create_block(parameters, desugar_body(body), span_of(node))
      end

      def desugar_return(node)
        value = @bareruby_ast.children_of(node)[0]
        @bareruby_ast.create_return(value && desugar_node(value), span_of(node))
      end

      def desugar_body(statements)
        statements.map { |statement| desugar_node(statement) }
      end

      def desugar_method_body(statements)
        body = desugar_body(statements)
        return body if body.empty?

        last = body[-1]
        return body if @bareruby_ast.node_type(last) == :return

        body[0...-1] + [@bareruby_ast.create_return(last, span_of(last))]
      end

      def span_of(node) = @bareruby_ast.span_of(node)
    end
  end
end
