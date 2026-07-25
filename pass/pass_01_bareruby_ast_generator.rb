# frozen_string_literal: true

require "prism"

require_relative "../ir/bareruby_ast"

module BareRubyProt
  module Pass
    class BareRubyAstGenerator
      attr_reader :result

      def initialize(source_file_name)
        @source_file_name = source_file_name
      end

      def run
        prism = Prism.parse_file(@source_file_name)
        @result = BareRubyAST.new(@source_file_name)
        read_prism_ast(prism.value)

        self
      end

      def read_prism_ast(node)
        case node
        when Prism::ProgramNode
          @result.replace_program(read_statements(node.statements), span_of(node))
        when Prism::IntegerNode
          @result.create_integer(node.value, span_of(node))
        when Prism::LocalVariableReadNode
          @result.create_reference(:local, node.name, span_of(node))
        when Prism::InstanceVariableReadNode
          @result.create_reference(:instance, node.name, span_of(node))
        when Prism::ConstantReadNode
          @result.create_reference(:constant, node.name, span_of(node))
        when Prism::ConstantPathNode
          @result.create_constant_path(node.parent.name, node.name, span_of(node))
        when Prism::LocalVariableWriteNode
          create_assignment(:local, node)
        when Prism::InstanceVariableWriteNode
          create_assignment(:instance, node)
        when Prism::LocalVariableOperatorWriteNode
          create_compound_assignment(:local, node)
        when Prism::InstanceVariableOperatorWriteNode
          create_compound_assignment(:instance, node)
        when Prism::RequiredParameterNode
          @result.create_parameter(node.name, span_of(node))
        when Prism::DefNode
          @result.create_method_definition(
            node.name,
            read_parameters(node.parameters),
            read_statements(node.body),
            span_of(node)
          )
        when Prism::ClassNode
          @result.create_subclass_definition(
            node.constant_path.name,
            node.superclass&.name || :Object,
            read_statements(node.body),
            span_of(node)
          )
        when Prism::CallNode
          @result.create_call(
            read_optional_node(node.receiver),
            node.name,
            read_arguments(node.arguments),
            read_optional_node(node.block),
            span_of(node)
          )
        when Prism::BlockNode
          @result.create_block(
            read_block_parameters(node.parameters),
            read_statements(node.body),
            span_of(node)
          )
        when Prism::ReturnNode
          @result.create_return(read_arguments(node.arguments).first, span_of(node))
        when Prism::BreakNode
          @result.create_iteration_control(:break, span_of(node))
        when Prism::NextNode
          @result.create_iteration_control(:next, span_of(node))
        when Prism::ParenthesesNode
          read_statements(node.body).fetch(0)
        end
      end

      def read_statements(node)
        node ? node.body.map { |child| read_prism_ast(child) } : []
      end

      def read_parameters(node)
        node ? node.requireds.map { |parameter| read_prism_ast(parameter) } : []
      end

      def read_block_parameters(node)
        node ? read_parameters(node.parameters) : []
      end

      def read_arguments(node)
        node ? node.arguments.map { |argument| read_prism_ast(argument) } : []
      end

      def read_optional_node(node)
        read_prism_ast(node) if node
      end

      def create_assignment(kind, node)
        target = @result.create_reference(kind, node.name, span_of_location(node.name_loc))
        @result.create_assignment(target, read_prism_ast(node.value), span_of(node))
      end

      def create_compound_assignment(kind, node)
        target = @result.create_reference(kind, node.name, span_of_location(node.name_loc))
        @result.create_compound_assignment(
          target,
          node.binary_operator,
          read_prism_ast(node.value),
          span_of(node)
        )
      end

      def span_of(node) = span_of_location(node.location)

      def span_of_location(location)
        @result.create_span(
          location.start_offset, location.start_line, location.start_column,
          location.end_offset, location.end_line, location.end_column
        )
      end
    end
  end
end
