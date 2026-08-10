# frozen_string_literal: true

module BareRubyProt
  module Pass
    class BlockInliner
      attr_reader :result

      def initialize(typed_ast)
        @tast = typed_ast
      end

      def run
        body = @tast.program_body.map { |statement| inline_node(statement) }
        @result = @tast.replace_program(body)

        self
      end

      def inline_node(node)
        case @tast.node_type(node)
        when :class_definition then inline_class_definition(node)
        when :method_definition then inline_method_definition(node)
        when :assignment then inline_assignment(node)
        when :return then inline_return(node)
        when :call then inline_call(node)
        when :interrupt then inline_interrupt(node)
        when :if then inline_if(node)
        when :while then inline_while(node)
        when :begin then inline_begin(node)
        when :logical then inline_logical(node)
        when :arena then inline_arena(node)
        when :arena_alloc then inline_arena_alloc(node)
        when :arena_length then inline_arena_length(node)
        when :arena_dup then inline_arena_dup(node)
        when :arena_push then inline_arena_push(node)
        when :arena_index_assign then inline_arena_index_assign(node)
        when :array then inline_array(node)
        when :array_fill then inline_array_fill(node)
        when :array_dup then inline_array_dup(node)
        when :index then inline_index(node)
        when :index_assign then inline_index_assign(node)
        else node
        end
      end

      def inline_arena(node)
        size, body = @tast.children_of(node)
        @tast.create_arena(size, inline_body(body), span_of(node))
      end

      def inline_arena_alloc(node)
        length, initial, type = @tast.children_of(node)
        @tast.create_arena_alloc(inline_node(length), initial && inline_node(initial), type, span_of(node))
      end

      def inline_arena_length(node)
        receiver, type = @tast.children_of(node)
        @tast.create_arena_length(inline_node(receiver), type, span_of(node))
      end

      def inline_arena_dup(node)
        receiver, type = @tast.children_of(node)
        @tast.create_arena_dup(inline_node(receiver), type, span_of(node))
      end

      def inline_arena_push(node)
        receiver, value, type = @tast.children_of(node)
        @tast.create_arena_push(inline_node(receiver), inline_node(value), type, span_of(node))
      end

      def inline_arena_index_assign(node)
        receiver, index, value, type = @tast.children_of(node)
        @tast.create_arena_index_assign(
          inline_node(receiver), inline_node(index), inline_node(value), type, span_of(node)
        )
      end

      def inline_array(node)
        elements, type = @tast.children_of(node)
        @tast.create_array(elements.map { |element| inline_node(element) }, type, span_of(node))
      end

      def inline_array_fill(node)
        value, type = @tast.children_of(node)
        @tast.create_array_fill(value && inline_node(value), type, span_of(node))
      end

      def inline_array_dup(node)
        receiver, type = @tast.children_of(node)
        @tast.create_array_dup(inline_node(receiver), type, span_of(node))
      end

      def inline_index(node)
        receiver, index, type = @tast.children_of(node)
        @tast.create_index(inline_node(receiver), inline_node(index), type, span_of(node))
      end

      def inline_index_assign(node)
        receiver, index, value, type = @tast.children_of(node)
        @tast.create_index_assign(
          inline_node(receiver), inline_node(index), inline_node(value), type, span_of(node)
        )
      end

      def inline_if(node)
        condition, then_body, else_body, type = @tast.children_of(node)
        @tast.create_if(
          inline_node(condition), inline_body(then_body), else_body && inline_body(else_body),
          type, span_of(node)
        )
      end

      def inline_begin(node)
        body, rescue_body = @tast.children_of(node)
        @tast.create_begin(inline_body(body), inline_body(rescue_body), span_of(node))
      end

      def inline_while(node)
        condition, body = @tast.children_of(node)
        @tast.create_while(inline_node(condition), inline_body(body), span_of(node))
      end

      def inline_logical(node)
        operator, left, right, type = @tast.children_of(node)
        @tast.create_logical(operator, inline_node(left), inline_node(right), type, span_of(node))
      end

      def inline_class_definition(node)
        name, ivars, methods = @tast.children_of(node)
        @tast.create_class_definition(name, ivars, methods.map { |method| inline_node(method) }, span_of(node))
      end

      def inline_method_definition(node)
        identity, parameters, body = @tast.children_of(node)
        @tast.create_method_definition(identity, parameters, inline_body(body), span_of(node))
      end

      def inline_assignment(node)
        binding, value, type = @tast.children_of(node)
        @tast.create_assignment(binding, inline_node(value), type, span_of(node))
      end

      def inline_return(node)
        value, type = @tast.children_of(node)
        @tast.create_return(value && inline_node(value), type, span_of(node))
      end

      def inline_call(node)
        receiver, callee, arguments, block, type = @tast.children_of(node)
        return expand_iteration(node) if block && callee[:kind] == :builtin_iterator

        @tast.create_call(
          receiver && inline_node(receiver),
          callee,
          arguments.map { |argument| inline_node(argument) },
          block,
          type,
          span_of(node)
        )
      end

      def inline_interrupt(node)
        receiver, arguments, block, function, type = @tast.children_of(node)
        parameters, body, block_type = @tast.children_of(block)
        @tast.create_interrupt(
          inline_node(receiver), arguments.map { |argument| inline_node(argument) },
          @tast.create_block(parameters, inline_body(body), block_type, span_of(block)),
          function, type, span_of(node)
        )
      end

      def expand_iteration(node)
        receiver, callee, arguments, block, = @tast.children_of(node)
        span = span_of(node)
        body = inline_body(@tast.children_of(block)[1])

        case callee[:name]
        when :times
          parameter = @tast.children_of(block)[0].first
          binding, element_type = @tast.children_of(parameter)
          start_value = @tast.create_integer(0, element_type, span)
          @tast.create_for_range(binding, element_type, start_value, inline_node(receiver), false, body, span)
        when :upto
          parameter = @tast.children_of(block)[0].first
          binding, element_type = @tast.children_of(parameter)
          @tast.create_for_range(
            binding, element_type, inline_node(receiver), inline_node(arguments.first), true, body, span
          )
        when :loop
          @tast.create_while_true(body, span)
        end
      end

      def inline_body(statements) = statements.map { |statement| inline_node(statement) }

      def span_of(node) = @tast.span_of(node)
    end
  end
end
