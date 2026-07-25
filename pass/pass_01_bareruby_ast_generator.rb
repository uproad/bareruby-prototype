# frozen_string_literal: true

require "prism"

require_relative "../ir/bareruby_ast"

module BareRubyProt
  module Pass
    class BareRubyAstGenerator
      REQUIRE_NAMES = %i[require require_relative].freeze
      BUILTIN_REQUIRES = %w[gpio uart pwm i2c spi adc machine].freeze

      attr_reader :result, :notices

      def initialize(source_file_name)
        @source_file_name = File.expand_path(source_file_name)
        @loaded = [@source_file_name]
        @files = [@source_file_name]
        @notices = []
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
        when Prism::FloatNode
          @result.create_float(node.value, span_of(node))
        when Prism::SymbolNode
          @result.create_symbol(node.unescaped.to_sym, span_of(node))
        when Prism::StringNode
          @result.create_string(node.unescaped, span_of(node))
        when Prism::InterpolatedStringNode
          @result.create_interpolation(node.parts.map { |part| read_prism_ast(part) }, span_of(node))
        when Prism::EmbeddedStatementsNode
          read_statements(node.statements).fetch(0)
        when Prism::TrueNode
          @result.create_boolean(true, span_of(node))
        when Prism::FalseNode
          @result.create_boolean(false, span_of(node))
        when Prism::IfNode
          @result.create_if(
            read_prism_ast(node.predicate),
            read_statements(node.statements),
            read_branch(node.subsequent),
            span_of(node)
          )
        when Prism::UnlessNode
          @result.create_if(
            negate(read_prism_ast(node.predicate), span_of(node.predicate)),
            read_statements(node.statements),
            read_branch(node.else_clause),
            span_of(node)
          )
        when Prism::ElseNode
          read_statements(node.statements)
        when Prism::WhileNode
          @result.create_while(read_prism_ast(node.predicate), read_statements(node.statements), span_of(node))
        when Prism::UntilNode
          @result.create_while(
            negate(read_prism_ast(node.predicate), span_of(node.predicate)),
            read_statements(node.statements),
            span_of(node)
          )
        when Prism::AndNode
          @result.create_logical(:and, read_prism_ast(node.left), read_prism_ast(node.right), span_of(node))
        when Prism::OrNode
          @result.create_logical(:or, read_prism_ast(node.left), read_prism_ast(node.right), span_of(node))
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
        when Prism::BeginNode
          @result.create_begin(
            read_statements(node.statements),
            node.rescue_clause ? read_statements(node.rescue_clause.statements) : [],
            span_of(node)
          )
        when Prism::ModuleNode
          @result.create_module_definition(
            node.constant_path.name, read_statements(node.body), span_of(node)
          )
        when Prism::SuperNode
          @result.create_super(read_arguments(node.arguments), span_of(node))
        when Prism::ForwardingSuperNode
          @result.create_super([], span_of(node))
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
        return [] unless node

        node.body.flat_map do |child|
          target = require_target(child)
          target ? expand_require(*target, child) : [read_prism_ast(child)]
        end
      end

      def require_target(node)
        return unless node.is_a?(Prism::CallNode) && REQUIRE_NAMES.include?(node.name)

        argument = node.arguments&.arguments&.first
        [node.name, argument.unescaped] if argument.is_a?(Prism::StringNode)
      end

      # require is a compile-time splice with no runtime machinery (LANGUAGE.md section
      # 5.11). A file expands once; the second require of it is a no-op, which is also
      # what makes a cycle harmless rather than an error, since the compiler counts the
      # top-level file as require #0.
      def expand_require(kind, target, node)
        if kind == :require && BUILTIN_REQUIRES.include?(target)
          @notices << "notice: require #{target.inspect} is unnecessary; it is built in."
          return []
        end

        path = File.expand_path("#{target}.rb", File.dirname(@files.last))
        return [] if @loaded.include?(path)
        return [read_prism_ast(node)] unless File.exist?(path)

        @loaded << path
        @files.push(path)
        statements = read_statements(Prism.parse_file(path).value.statements)
        @files.pop
        statements
      end

      def read_parameters(node)
        node ? node.requireds.map { |parameter| read_prism_ast(parameter) } : []
      end

      def read_block_parameters(node)
        node ? read_parameters(node.parameters) : []
      end

      # Keyword arguments arrive bundled in a hash node; they become their own argument
      # nodes so the call keeps one flat, ordered argument list.
      def read_arguments(node)
        return [] unless node

        node.arguments.flat_map do |argument|
          if argument.is_a?(Prism::KeywordHashNode)
            argument.elements.map do |element|
              @result.create_keyword_argument(
                element.key.unescaped.to_sym, read_prism_ast(element.value), span_of(element)
              )
            end
          else
            [read_prism_ast(argument)]
          end
        end
      end

      def read_optional_node(node)
        read_prism_ast(node) if node
      end

      # An elsif arrives as a nested IfNode, an else as an ElseNode. Both become the
      # else body of the enclosing if.
      def read_branch(node)
        return unless node

        node.is_a?(Prism::ElseNode) ? read_statements(node.statements) : [read_prism_ast(node)]
      end

      def negate(node, span)
        @result.create_call(node, :!, [], nil, span)
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
