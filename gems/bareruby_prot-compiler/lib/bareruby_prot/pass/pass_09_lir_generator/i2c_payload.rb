# frozen_string_literal: true

module BareRubyProt
  # The bytes one I2C call sends. A program writes whatever it has — an integer, a static
  # string, a fixed-capacity array, an array or a string from a region — and all of it has
  # to reach the bus as one contiguous sequence, because one call in Ruby is one
  # transaction on the wire. They are appended in order to a string taken from the region
  # the call was given, which is also what makes the length a run-time answer.
  class I2cPayload
    def initialize(low_ir, typed_ast, value_layout, function_scope)
      @lir = low_ir
      @tast = typed_ast
      @value_layout = value_layout
      @function_scope = function_scope
    end

    # Each output is lowered as it is appended, by the block, because what an output is
    # made of is the pass's recursion rather than this one's business.
    def flattened(arena_reference, outputs, &lower)
      return [[], @lir.create_const_string(""), @lir.create_const_int(0, :int32)] if outputs.empty?

      name = @function_scope.next_temporary
      buffer = @lir.create_local(name, string_type)
      create = @lir.create_call(
        :bareruby_string_new, [arena_reference, @lir.create_const_string("")], string_type
      )
      statements = [@lir.create_declare(name, string_type, create)]
      outputs.each { |output| statements.concat(appended(buffer, output, &lower)) }

      [statements, bytes_of(buffer), length_of(buffer)]
    end

    private

    def string_type = @value_layout.arena_string_type

    def bytes_of(expression) = @lir.create_call(:bareruby_string_bytes, [expression], :string_ptr)

    def length_of(expression) = @lir.create_call(:bareruby_string_length, [expression], :int32)

    def appended(buffer, node, &lower)
      type = @tast.value_type(node)
      statements, expression = lower.call(node)
      return statements + [append(buffer, :bareruby_string_append_byte, [expression])] if integer?(type)
      return statements + [static_string(buffer, node, expression)] if type == :String

      if @value_layout.arena_string?(type)
        arguments = [bytes_of(expression), length_of(expression)]
        return statements + [append(buffer, :bareruby_string_append_bytes, arguments)]
      end

      statements + [element_loop(buffer, type, expression)]
    end

    def integer?(type) = type.is_a?(Symbol) && type.to_s.start_with?("Int")

    def append(buffer, function, arguments)
      @lir.create_expression(@lir.create_call(function, [buffer] + arguments, string_type))
    end

    # A literal is the one output whose length is known here, so it is appended without
    # the runtime measuring it.
    def static_string(buffer, node, expression)
      return append(buffer, :bareruby_string_append, [expression]) unless @tast.node_type(node) == :string

      length = @lir.create_const_int(@tast.children_of(node)[0].bytesize, :int32)
      append(buffer, :bareruby_string_append_bytes, [expression, length])
    end

    # An array goes on a byte at a time. A fixed-capacity one knows how many while
    # compiling; one from a region carries its length.
    def element_loop(buffer, type, expression)
      counter = @function_scope.next_temporary
      local = @lir.create_local(counter, :int32)
      limit = if @value_layout.array?(type)
                @lir.create_const_int(@value_layout.capacity_of(type), :int32)
              else
                @value_layout.length_of(expression)
              end
      element = @lir.create_index(
        @value_layout.items_of(expression), local, @value_layout.type_of(@value_layout.element_of(type))
      )
      @lir.create_for(
        @lir.create_declare(counter, :int32, @lir.create_const_int(0, :int32)),
        @lir.create_binary("<", local, limit, :bool),
        @lir.create_assign(local, @lir.create_binary("+", local, @lir.create_const_int(1, :int32), :int32)),
        [append(buffer, :bareruby_string_append_byte, [element])]
      )
    end
  end
end
