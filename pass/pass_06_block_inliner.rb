# frozen_string_literal: true

module BareRubyProt
  module Pass
    class BlockInliner
      attr_reader :result

      def initialize(typed_ir)
        @tir = typed_ir
      end

      def run
        body = @tir.program_body.map { |statement| inline_node(statement) }
        @result = @tir.replace_program(body)

        self
      end

      def inline_node(node)
        case @tir.node_type(node)
        when :class_definition then inline_class_definition(node)
        when :method_definition then inline_method_definition(node)
        when :assignment then inline_assignment(node)
        when :return then inline_return(node)
        when :call then inline_call(node)
        when :if then inline_if(node)
        when :while then inline_while(node)
        when :begin then inline_begin(node)
        when :logical then inline_logical(node)
        when :arena then inline_arena(node)
        when :arena_alloc then inline_arena_alloc(node)
        when :arena_length then inline_arena_length(node)
        when :array then inline_array(node)
        when :array_fill then inline_array_fill(node)
        when :array_dup then inline_array_dup(node)
        when :index then inline_index(node)
        when :index_assign then inline_index_assign(node)
        else node
        end
      end

      def inline_arena(node)
        binding, size, body = @tir.children_of(node)
        @tir.create_arena(binding, size, inline_body(body), span_of(node))
      end

      def inline_arena_alloc(node)
        receiver, length, type = @tir.children_of(node)
        @tir.create_arena_alloc(inline_node(receiver), inline_node(length), type, span_of(node))
      end

      def inline_arena_length(node)
        receiver, type = @tir.children_of(node)
        @tir.create_arena_length(inline_node(receiver), type, span_of(node))
      end

      def inline_array(node)
        elements, type = @tir.children_of(node)
        @tir.create_array(elements.map { |element| inline_node(element) }, type, span_of(node))
      end

      def inline_array_fill(node)
        value, type = @tir.children_of(node)
        @tir.create_array_fill(value && inline_node(value), type, span_of(node))
      end

      def inline_array_dup(node)
        receiver, type = @tir.children_of(node)
        @tir.create_array_dup(inline_node(receiver), type, span_of(node))
      end

      def inline_index(node)
        receiver, index, type = @tir.children_of(node)
        @tir.create_index(inline_node(receiver), inline_node(index), type, span_of(node))
      end

      def inline_index_assign(node)
        receiver, index, value, type = @tir.children_of(node)
        @tir.create_index_assign(
          inline_node(receiver), inline_node(index), inline_node(value), type, span_of(node)
        )
      end

      def inline_if(node)
        condition, then_body, else_body, type = @tir.children_of(node)
        @tir.create_if(
          inline_node(condition), inline_body(then_body), else_body && inline_body(else_body),
          type, span_of(node)
        )
      end

      def inline_begin(node)
        body, rescue_body = @tir.children_of(node)
        @tir.create_begin(inline_body(body), inline_body(rescue_body), span_of(node))
      end

      def inline_while(node)
        condition, body = @tir.children_of(node)
        @tir.create_while(inline_node(condition), inline_body(body), span_of(node))
      end

      def inline_logical(node)
        operator, left, right, type = @tir.children_of(node)
        @tir.create_logical(operator, inline_node(left), inline_node(right), type, span_of(node))
      end

      def inline_class_definition(node)
        name, ivars, methods = @tir.children_of(node)
        @tir.create_class_definition(name, ivars, methods.map { |method| inline_node(method) }, span_of(node))
      end

      def inline_method_definition(node)
        identity, parameters, body = @tir.children_of(node)
        @tir.create_method_definition(identity, parameters, inline_body(body), span_of(node))
      end

      def inline_assignment(node)
        binding, value, type = @tir.children_of(node)
        @tir.create_assignment(binding, inline_node(value), type, span_of(node))
      end

      def inline_return(node)
        value, type = @tir.children_of(node)
        @tir.create_return(value && inline_node(value), type, span_of(node))
      end

      def inline_call(node)
        receiver, callee, arguments, block, type = @tir.children_of(node)
        return expand_iteration(node) if block && callee[:kind] == :builtin_iterator

        @tir.create_call(
          receiver && inline_node(receiver),
          callee,
          arguments.map { |argument| inline_node(argument) },
          block,
          type,
          span_of(node)
        )
      end

      def expand_iteration(node)
        receiver, callee, arguments, block, = @tir.children_of(node)
        span = span_of(node)
        body = inline_body(@tir.children_of(block)[1])

        case callee[:name]
        when :times
          parameter = @tir.children_of(block)[0].first
          binding, element_type = @tir.children_of(parameter)
          start_value = @tir.create_integer(0, element_type, span)
          @tir.create_for_range(binding, element_type, start_value, inline_node(receiver), false, body, span)
        when :upto
          parameter = @tir.children_of(block)[0].first
          binding, element_type = @tir.children_of(parameter)
          @tir.create_for_range(
            binding, element_type, inline_node(receiver), inline_node(arguments.first), true, body, span
          )
        when :loop
          @tir.create_while_true(body, span)
        end
      end

      def inline_body(statements) = statements.map { |statement| inline_node(statement) }

      def span_of(node) = @tir.span_of(node)
    end
  end
end
