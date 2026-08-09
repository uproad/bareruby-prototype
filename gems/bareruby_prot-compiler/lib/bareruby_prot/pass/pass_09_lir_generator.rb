# frozen_string_literal: true

require_relative "../ir/lir"
require_relative "pass_09_lir_generator/value_layout"
require_relative "pass_09_lir_generator/bytes_sent"
require_relative "pass_09_lir_generator/arena_storage"
require_relative "pass_09_lir_generator/binding_storage"
require_relative "pass_09_lir_generator/function_scope"

module BareRubyProt
  module Pass
    class LirGenerator
      OPERATOR_TEXT = {
        :+ => "+", :- => "-", :* => "*", :/ => "/", :% => "%",
        :<< => "<<", :>> => ">>", :& => "&", :| => "|", :^ => "^",
        :== => "==", :!= => "!=", :< => "<", :<= => "<=", :> => ">", :>= => ">=",
        :-@ => "-", :~ => "~", :! => "!"
      }.freeze
      attr_reader :result

      def initialize(typed_ast)
        @tast = typed_ast
        @lir = LIR.new
        @value_layout = ValueLayout.new(@lir)
      end

      def run
        structs = []
        functions = []
        @interrupt_functions = []

        @tast.program_body.each do |statement|
          next unless class_definition?(statement)

          name, ivars, methods = @tast.children_of(statement)
          @binding_storage = BindingStorage.new(@lir, @tast, @value_layout, methods)
          fields = ivars.map do |ivar|
            @lir.create_field(@value_layout.field_name(ivar[:name]), @binding_storage.ivar_type(ivar))
          end
          structs << @lir.create_struct(name, fields)
          methods.each { |method| functions << lower_method(method) }
        end

        @binding_storage = BindingStorage.new(@lir, @tast, @value_layout, [])
        functions << lower_main
        functions.concat(@interrupt_functions)
        @result = @lir.replace_module(@value_layout.structs + structs, functions)

        self
      end

      def class_definition?(node) = @tast.node_type(node) == :class_definition

      def lower_method(node)
        identity, parameters, body = @tast.children_of(node)
        with_function(identity[:owner], identity[:return_type]) do
          lir_parameters = [{ name: :self, type: @function_scope.self_type }]
          parameters.each do |parameter|
            binding, type = @tast.children_of(parameter)
            @function_scope.declare(binding[:name])
            @function_scope.declare_pointer(binding[:name]) if @value_layout.shared?(type)
            lir_parameters << { name: binding[:name], type: @binding_storage.type_of(binding, type) }
          end

          statements = predeclare_nilable_locals(body) + body.flat_map { |statement| lower_statement(statement) }
          @lir.create_function(
            function_name(identity[:owner], identity[:name]),
            lir_parameters,
            @value_layout.value_type_of(identity[:return_type]),
            statements
          )
        end
      end

      def lower_main
        with_function(nil, :Nil) do
          body = @tast.program_body.reject { |node| class_definition?(node) }
          statements = predeclare_nilable_locals(body) + body.flat_map { |node| lower_statement(node) }
          @lir.create_function(:bareruby_main, [], :void, statements)
        end
      end

      def with_function(self_class, return_type)
        previous = @function_scope
        @function_scope = FunctionScope.new(
          self_type: self_class && @lir.pointer_type(@lir.struct_type(self_class)),
          return_type:, void_return: @value_layout.type_of(return_type) == :void
        )
        @binding_storage.scope = @function_scope
        yield
      ensure
        @function_scope = previous
        @binding_storage.scope = previous
      end

      # The handler, the realtime context it carries and the checks that follow (pass 11)
      # are the language's. **What is registered with is the node's to say** — the
      # registration arguments and the handler's parameters both arrived from the
      # peripheral's declaration and are not names known here.
      def lower_interrupt(node)
        receiver, arguments, block, function, = @tast.children_of(node)
        handler_name = :"bareruby_interrupt_handler_#{@interrupt_functions.length}"
        parameters, body, = @tast.children_of(block)

        receiver_statements, receiver_expression = lower_expression(receiver)
        lowered_arguments = arguments.map { |argument| lower_expression(argument) }
        @interrupt_functions << with_function(nil, :Nil) {
          lir_parameters = parameters.map do |parameter|
            binding, type = @tast.children_of(parameter)
            @function_scope.declare(binding[:name])
            { name: binding[:name], type: @binding_storage.type_of(binding, type) }
          end
          statements = predeclare_nilable_locals(body) + body.flat_map { |statement| lower_statement(statement) }
          @lir.create_function(handler_name, lir_parameters, :void, statements + [@lir.create_return(nil)], context: :realtime)
        }

        receiver_statements + lowered_arguments.flat_map(&:first) + [@lir.create_expression(
          @lir.create_call(
            function,
            [@lir.reference_to(receiver_expression)] + lowered_arguments.map(&:last) +
              [@lir.create_function_reference(handler_name)], :void
          )
        )]
      end

      # A local first assigned on only one control-flow path exists as T? outside it.
      # Its tagged storage therefore has to live before the branch, initially in the Nil
      # state, instead of being declared inside the arm where the first assignment occurs.
      def predeclare_nilable_locals(body)
        bindings = {}
        collect_nilable_bindings(body, bindings)
        bindings.values.filter_map do |binding|
          next if @function_scope.declared?(binding[:name])

          @function_scope.declare(binding[:name])
          type = binding[:type]
          @lir.create_declare(binding[:name], @value_layout.type_of(type), @value_layout.absent(type))
        end
      end

      def collect_nilable_bindings(value, bindings)
        return value.each { |element| collect_nilable_bindings(element, bindings) } if value.is_a?(Array)
        return unless value.is_a?(Hash) && value.key?(:children)
        return if @tast.node_type(value) == :arena

        if @tast.node_type(value) == :assignment
          binding = @tast.children_of(value)[0]
          bindings[binding[:name]] = binding if binding[:kind] == :local && @value_layout.nilable?(binding[:type])
        end
        collect_nilable_bindings(value[:children], bindings)
      end

      def lower_statement(node)
        case @tast.node_type(node)
        when :return then lower_return(node)
        when :for_range then lower_for_range(node)
        when :while_true then lower_while_true(node)
        when :arena then lower_arena(node)
        when :while then lower_while(node)
        when :if then lower_if_statement(node)
        when :begin
          body, rescue_body = @tast.children_of(node)
          [@lir.create_try(lower_body(body), lower_body(rescue_body))]
        when :iteration_control then lower_iteration_control(node)
        when :interrupt then lower_interrupt(node)
        else
          statements, value = lower_expression(node)
          value && value[:type] == :call ? statements + [@lir.create_expression(value)] : statements
        end
      end

      # Every method body ends in a return, because pass 2 wraps the last statement in one to
      # give Ruby its implicit return, so what is returned here is as often a statement as it
      # is a value. When the method returns nothing it stays a statement: the call still has
      # to be made and the loop still has to run, and neither leaves a value C++ could return.
      def lower_return(node)
        value = @tast.children_of(node)[0]
        return [@lir.create_return(nil)] if value.nil?
        # An implicit return wrapped around a construct that always leaves on its own.
        return lower_statement(value) if @tast.value_type(value) == :NoReturn
        return lower_statement(value) + [@lir.create_return(nil)] if @function_scope.void_return?

        statements, expression = lower_expression(value)
        statements + [@lir.create_return(coerce_value(value, expression, @function_scope.return_type))]
      end

      def lower_for_range(node)
        binding, type, start_value, limit_value, inclusive, body = @tast.children_of(node)
        element_type = @value_layout.type_of(type)
        start_statements, start_expression = lower_expression(start_value)
        limit_statements, limit_expression = lower_expression(limit_value)
        limit_name = @function_scope.next_temporary

        init = @lir.create_declare(binding[:name], element_type, start_expression)
        counter = @lir.create_local(binding[:name], element_type)
        condition = @lir.create_binary(
          inclusive ? "<=" : "<", counter, @lir.create_local(limit_name, element_type), :bool
        )
        step = @lir.create_assign(
          counter, @lir.create_binary("+", counter, @lir.create_const_int(1, element_type), element_type)
        )

        start_statements + limit_statements +
          [@lir.create_declare(limit_name, element_type, limit_expression),
           @lir.create_for(init, condition, step, lower_body(body))]
      end

      def lower_while_true(node)
        [@lir.create_while(@lir.create_const_bool(true), lower_body(@tast.children_of(node)[0]))]
      end

      # The region is a static buffer belonging to this one site rather than a slice of a
      # shared heap, which is what makes the RAM an arena costs visible in .bss and what
      # makes release a bump pointer reset. The guard is what releases it: its destructor
      # runs on the way out of the scope whether the block ends normally or an exception
      # leaves it, which is the exception safety the design requires.
      def lower_arena(node)
        size, body = @tast.children_of(node)
        buffer, guard = arena_storage.opened(size)
        [@lir.create_scope([buffer, guard] + lower_block_body(body))]
      end

      # A local the block introduces does not exist after it, in Ruby or in the C++ scope
      # the block becomes, so what was declared inside is forgotten on the way out and the
      # next block is free to use the same names.
      def lower_block_body(body)
        @function_scope.nested { predeclare_nilable_locals(body) + lower_body(body) }
      end

      # The runtime hands back a handle it owns, so there is nothing here to assemble. An
      # initial value is written afterwards; without one the elements are already the
      # default, because a fresh block from the region is zeroed.
      def lower_arena_alloc(node)
        length, initial, type = @tast.children_of(node)
        element = @value_layout.type_of(@value_layout.element_of(type))
        length_statements, length_expression = lower_expression(length)
        name = @function_scope.next_temporary
        place = @lir.create_local(name, @value_layout.type_of(type))

        statements = length_statements +
                     [@lir.create_declare(name, @value_layout.type_of(type),
                                          arena_storage.allocation(length_expression, element))]
        statements += filling(place, element, initial) if initial
        [statements, place]
      end

      # Filling walks the length the handle now carries rather than a capacity, which is
      # the one thing this array knows only at run time.
      def filling(place, element, initial)
        statements, expression = lower_expression(initial)
        source = @function_scope.next_temporary
        counter = @function_scope.next_temporary
        local = @lir.create_local(counter, :int32)

        statements + [@lir.create_declare(source, element, expression),
                      @lir.create_for(
                        @lir.create_declare(counter, :int32, @lir.create_const_int(0, :int32)),
                        @lir.create_binary("<", local, @value_layout.length_of(place), :bool),
                        @lir.create_assign(local, @lir.create_binary("+", local, @lir.create_const_int(1, :int32), :int32)),
                        [@lir.create_assign(
                          @lir.create_index(@value_layout.arena_items_of(place, element), local, element),
                          @lir.create_local(source, element)
                        )]
                      )]
      end

      def lower_arena_length(node)
        statements, expression = lower_expression(@tast.children_of(node)[0])
        [statements, @value_layout.length_of(expression)]
      end

      def lower_arena_current(_node) = [[], arena_storage.current]

      def lower_arena_dup(node)
        receiver, type = @tast.children_of(node)
        element = @value_layout.type_of(@value_layout.element_of(type))
        statements, expression = lower_expression(receiver)
        [statements, arena_storage.duplication(expression, element)]
      end

      # Writing may grow the array, and growing moves the elements, so the pointer the
      # write uses is the one the runtime hands back rather than one read beforehand.
      def lower_arena_index_assign(node)
        receiver, index, value, type = @tast.children_of(node)
        element = @value_layout.type_of(type)
        receiver_statements, receiver_expression = lower_expression(receiver)
        index_statements, index_expression = lower_expression(index)
        value_statements, value_expression = lower_expression(value)
        name = @function_scope.next_temporary
        local = @lir.create_local(name, :int32)
        statements = receiver_statements + index_statements + value_statements +
                     [@lir.create_declare(name, :int32, index_expression)]
        target = @lir.create_index(
          arena_storage.extension(
            receiver_expression, @lir.create_binary("+", local, @lir.create_const_int(1, :int32), :int32), element
          ), local, element
        )
        [statements + [@lir.create_assign(target, value_expression)], value_expression]
      end

      # Appending writes at the length the array has now, which the runtime reads for
      # itself: the index is bound first because extending changes it.
      def lower_arena_push(node)
        receiver, value, type = @tast.children_of(node)
        element = @value_layout.type_of(@value_layout.element_of(type))
        receiver_statements, receiver_expression = lower_expression(receiver)
        value_statements, value_expression = lower_expression(value)
        name = @function_scope.next_temporary
        local = @lir.create_local(name, :int32)
        statements = receiver_statements + value_statements +
                     [@lir.create_declare(name, :int32, @value_layout.length_of(receiver_expression))]
        target = @lir.create_index(
          arena_storage.extension(
            receiver_expression, @lir.create_binary("+", local, @lir.create_const_int(1, :int32), :int32), element
          ), local, element
        )
        [statements + [@lir.create_assign(target, value_expression)], receiver_expression]
      end

      def lower_condition(node)
        statements, expression = lower_expression(node)
        type = @tast.value_type(node)
        return [statements, expression] if type == :Bool
        return [statements, @lir.create_const_bool(false)] if type == :Nil
        return [statements, @value_layout.truth_of(expression, type)] if @value_layout.nilable?(type)

        [statements, @lir.create_const_bool(true)]
      end

      # C re-evaluates a while condition every iteration, so a condition that needs
      # statements of its own becomes an explicit test-and-break at the top of the body.
      def lower_while(node)
        condition, body = @tast.children_of(node)
        condition_statements, condition_expression = lower_condition(condition)
        return [@lir.create_while(condition_expression, lower_body(body))] if condition_statements.empty?

        guard = @lir.create_if(
          @lir.create_unary("!", condition_expression, :bool), [@lir.create_break], nil
        )
        [@lir.create_while(@lir.create_const_bool(true), condition_statements + [guard] + lower_body(body))]
      end

      def lower_if_statement(node)
        condition, then_body, else_body, = @tast.children_of(node)
        condition_statements, condition_expression = lower_condition(condition)
        condition_statements +
          [@lir.create_if(condition_expression, lower_body(then_body), else_body && lower_body(else_body))]
      end

      def lower_iteration_control(node)
        [@tast.children_of(node)[0] == :break ? @lir.create_break : @lir.create_next]
      end

      def lower_body(statements) = statements.flat_map { |statement| lower_statement(statement) }

      def lower_expression(node)
        case @tast.node_type(node)
        when :integer
          value, type = @tast.children_of(node)
          [[], @lir.create_const_int(value, @value_layout.type_of(type))]
        when :nil
          [[], nil]
        when :reference
          lower_reference(node)
        when :boolean
          value, = @tast.children_of(node)
          [[], @lir.create_const_bool(value)]
        when :string
          value, = @tast.children_of(node)
          [[], @lir.create_const_string(value)]
        when :assignment
          lower_assignment(node)
        when :index
          lower_index(node)
        when :index_assign
          lower_index_assign(node)
        when :array, :array_fill, :array_dup
          lower_array_temporary(node)
        when :arena_alloc
          lower_arena_alloc(node)
        when :arena_length
          lower_arena_length(node)
        when :arena_current
          lower_arena_current(node)
        when :arena_dup
          lower_arena_dup(node)
        when :arena_push
          lower_arena_push(node)
        when :arena_index_assign
          lower_arena_index_assign(node)
        when :call
          lower_call(node)
        when :logical
          lower_logical(node)
        when :if
          lower_if_expression(node)
        end
      end

      def lower_logical(node)
        operator, left, right, type = @tast.children_of(node)
        return lower_expression(right) if operator == :or && @tast.value_type(left) == :Nil
        return lower_nilable_logical(operator, left, right, type) if @value_layout.nilable?(@tast.value_type(left))

        left_statements, left_expression = lower_expression(left)
        right_statements, right_expression = lower_expression(right)
        [left_statements + right_statements,
         @lir.create_binary(operator == :and ? "&&" : "||", left_expression, right_expression, @value_layout.type_of(type))]
      end

      def lower_nilable_logical(operator, left, right, type)
        left_statements, left_expression = lower_expression(left)
        left_type = @tast.value_type(left)
        left_name = @function_scope.next_temporary
        left_local_type = @value_layout.value_type_of(left_type)
        left_local = @lir.create_local(left_name, left_local_type)
        result_name = @function_scope.next_temporary
        result_type = @value_layout.value_type_of(type)
        result = @lir.create_local(result_name, result_type)
        statements = left_statements + [
          @lir.create_declare(left_name, left_local_type, left_expression),
          @lir.create_declare(result_name, result_type, nil)
        ]

        if operator == :or
          present = @lir.create_assign(result, @value_layout.value_of(left_local, left_type))
          absent = lower_expression_into(right, result, type)
        else
          present = lower_expression_into(right, result, type)
          absent = [@lir.create_assign(result, @value_layout.absent(type))]
        end
        statements << @lir.create_if(@value_layout.truth_of(left_local, left_type), [present].flatten, absent)
        [statements, result]
      end

      # An if used as a value becomes a declaration plus branches that assign into it.
      def lower_if_expression(node)
        condition, then_body, else_body, type = @tast.children_of(node)
        result_type = @value_layout.value_type_of(type)
        result_name = @function_scope.next_temporary
        condition_statements, condition_expression = lower_condition(condition)

        statements = condition_statements + [@lir.create_declare(result_name, result_type, nil)]
        statements << @lir.create_if(
          condition_expression,
          lower_body_into(then_body, result_name, type),
          else_body ? lower_body_into(else_body, result_name, type) :
            [@lir.create_assign(@lir.create_local(result_name, result_type), @value_layout.absent(type))]
        )
        [statements, @lir.create_local(result_name, result_type)]
      end

      def lower_body_into(statements, result_name, type)
        result_type = @value_layout.value_type_of(type)
        return [@lir.create_assign(@lir.create_local(result_name, result_type), @value_layout.absent(type))] if statements.empty?

        leading = statements[0...-1].flat_map { |statement| lower_statement(statement) }
        value_statements, value_expression = lower_expression(statements.last)
        leading + value_statements +
          [@lir.create_assign(@lir.create_local(result_name, result_type),
                              coerce_value(statements.last, value_expression, type))]
      end

      def lower_expression_into(node, place, type)
        statements, expression = lower_expression(node)
        statements + [@lir.create_assign(place, coerce_value(node, expression, type))]
      end

      # An interpolation assigned to a local becomes a buffer of the size pass 5 bounded
      # plus one formatting call into it. The local is the buffer, so every later
      # reference to it already reads as a const char *.
      def lower_format_assignment(binding, value)
        capacity, format, values, = @tast.children_of(value)
        statements, format_expression = lower_expression(format)
        argument_statements, argument_expressions = lower_arguments(values)
        place = @lir.create_local(binding[:name], :string_ptr)
        @function_scope.declare(binding[:name])

        call = @lir.create_call(
          :bareruby_format,
          [place, @lir.create_const_int(capacity, :int32), format_expression] + argument_expressions,
          :void
        )
        [[@lir.create_declare_buffer(binding[:name], capacity)] + statements + argument_statements +
          [@lir.create_expression(call)], place]
      end

      # Reading stays pointer arithmetic in both arrays. The growing one keeps its elements
      # as bytes because the runtime does not know what they are, so the read casts them
      # back — the arithmetic is the same, the type is restored on the way in.
      def lower_index(node)
        receiver, index, type = @tast.children_of(node)
        element = @value_layout.type_of(type)
        receiver_statements, receiver_expression = lower_expression(receiver)
        index_statements, index_expression = lower_expression(index)
        items = if @value_layout.arena_array?(@tast.value_type(receiver))
                  @value_layout.arena_items_of(receiver_expression, element)
                else
                  @value_layout.items_of(receiver_expression)
                end
        [receiver_statements + index_statements, @lir.create_index(items, index_expression, element)]
      end

      def lower_index_assign(node)
        receiver, index, value, type = @tast.children_of(node)
        receiver_statements, receiver_expression = lower_expression(receiver)
        index_statements, index_expression = lower_expression(index)
        value_statements, value_expression = lower_expression(value)
        place = @lir.create_index(@value_layout.items_of(receiver_expression), index_expression, @value_layout.type_of(type))

        [receiver_statements + index_statements + value_statements +
          [@lir.create_assign(place, value_expression)], place]
      end

      def lower_assignment(node)
        binding, value, type = @tast.children_of(node)
        return lower_format_assignment(binding, value) if @tast.node_type(value) == :format
        storage_type = binding[:type] || type
        unless @value_layout.nilable?(storage_type)
          return lower_array_assignment(binding, value, type) if @binding_storage.array_creation?(value)
          return lower_object_assignment(binding, value, type) if @binding_storage.object_creation?(value)
        end

        statements, value_expression = lower_expression(value)
        @function_scope.declare_pointer(binding[:name]) if @value_layout.shared?(type) && binding[:kind] == :local
        value_expression = coerce_value(value, value_expression, storage_type)
        place = place_of(binding, @binding_storage.type_of(binding, storage_type))

        if binding[:kind] == :local && !@function_scope.declared?(binding[:name])
          @function_scope.declare(binding[:name])
          written = statements + [
            @lir.create_declare(binding[:name], @binding_storage.type_of(binding, storage_type), value_expression)
          ]
        else
          written = statements + [@lir.create_assign(place, value_expression)]
        end
        [written, read_nilable_place(place, storage_type, type)]
      end

      def lower_reference(node)
        binding, type = @tast.children_of(node)
        storage_type = @value_layout.nilable?(binding[:type]) ? binding[:type] : type
        place = place_of(binding, @binding_storage.type_of(binding, storage_type))
        [[], read_nilable_place(place, storage_type, type)]
      end

      def read_nilable_place(place, storage_type, flow_type)
        return place unless @value_layout.nilable?(storage_type) && !@value_layout.nilable?(flow_type)

        @value_layout.value_of(place, storage_type)
      end

      def coerce_value(node, expression, target_type)
        source_type = @tast.value_type(node)
        return @value_layout.absent(target_type) if @value_layout.nilable?(target_type) && source_type == :Nil
        if @value_layout.nilable?(target_type) && !@value_layout.nilable?(source_type)
          return @lir.create_brace_init(
            [@lir.create_const_bool(true), @binding_storage.rvalue(node, expression)], @value_layout.type_of(target_type)
          )
        end

        @binding_storage.rvalue(node, expression)
      end

      # Every object is shared, which is what Ruby does. Assignment names the same object
      # rather than copying it, so only the binding a creation expression is assigned to owns
      # storage and every other binding of that type is a pointer to somebody else's. Passing
      # an object to a method is that same assignment: a method that changes what it was
      # handed changes the caller's object, where a copy would take every change with it when
      # the call dropped it. An arena has a second reason — what it hands out is recorded in
      # the arena itself, so a method that allocated from a copy would leave the caller's
      # arena believing the room is still free.
      # A creation expression is where storage comes from, so the binding it is assigned to
      # holds the array itself rather than a pointer to one.
      def lower_array_assignment(binding, value, type)
        struct = @value_layout.type_of(type)
        place = place_of(binding, struct)
        [@binding_storage.declaration(binding, struct) + fill_of(place, value, type), place]
      end

      # The same for an object: the binding a constructor is assigned to holds the instance,
      # and the constructor writes straight into it rather than into a temporary that would
      # then have to be copied there.
      def lower_object_assignment(binding, value, type)
        _receiver, callee, arguments, = @tast.children_of(value)
        struct = @value_layout.type_of(type)
        place = place_of(binding, struct)
        [@binding_storage.object_declaration(binding, struct) + construction_of(place, callee, arguments), place]
      end

      # An array written anywhere other than the right of an assignment still needs
      # storage to fill, so it gets a temporary of its own.
      def lower_array_temporary(node)
        type = @tast.value_type(node)
        struct = @value_layout.type_of(type)
        place = @lir.create_local(@function_scope.next_temporary, struct)
        [[@lir.create_declare(@lir.children_of(place)[0], struct, nil)] + fill_of(place, node, type), place]
      end

      def fill_of(place, value, type)
        case @tast.node_type(value)
        when :array then fill_from_elements(place, value)
        when :array_dup then fill_from_copy(place, value)
        else fill_from_value(place, value, type)
        end
      end

      # dup is the only thing that duplicates an array. The wrapper struct makes it one
      # assignment, dereferencing the source when it is a pointer to somebody else's
      # storage.
      def fill_from_copy(place, value)
        receiver, type = @tast.children_of(value)
        struct = @value_layout.type_of(type)
        statements, expression = lower_expression(receiver)
        source = @lir.pointer_type?(@lir.value_type(expression)) ? @lir.create_unary("*", expression, struct) : expression
        statements + [@lir.create_assign(place, source)]
      end

      def fill_from_elements(place, value)
        elements, = @tast.children_of(value)
        elements.each_with_index.flat_map do |element, position|
          element_statements, element_expression = lower_expression(element)
          slot = @lir.create_index(
            @value_layout.items_of(place), @lir.create_const_int(position, :int32), @lir.value_type(element_expression)
          )
          element_statements + [@lir.create_assign(slot, element_expression)]
        end
      end

      # Array.new evaluates its initial value once, so it is bound to a temporary before
      # the loop rather than re-evaluated per element. Array.new(n) has no initial value at
      # all and leaves the storage untouched.
      def fill_from_value(place, value, type)
        fill_value, = @tast.children_of(value)
        return [] if fill_value.nil?

        element_type = @value_layout.type_of(@value_layout.element_of(type))
        statements, expression = lower_expression(fill_value)
        source = @function_scope.next_temporary
        counter = @function_scope.next_temporary
        local = @lir.create_local(counter, :int32)

        statements + [@lir.create_declare(source, element_type, expression),
                      @lir.create_for(
                        @lir.create_declare(counter, :int32, @lir.create_const_int(0, :int32)),
                        @lir.create_binary("<", local, @lir.create_const_int(@value_layout.capacity_of(type), :int32), :bool),
                        @lir.create_assign(local, @lir.create_binary("+", local, @lir.create_const_int(1, :int32), :int32)),
                        [@lir.create_assign(
                          @lir.create_index(@value_layout.items_of(place), local, element_type),
                          @lir.create_local(source, element_type)
                        )]
                      )]
      end

      def lower_call(node)
        receiver, callee, arguments, _block, type = @tast.children_of(node)
        case callee[:kind]
        when :builtin_operator then lower_operator(receiver, callee, arguments, type)
        when :builtin_nil_p then lower_nil_predicate(receiver)
        when :builtin_puts, :builtin_printf, :builtin_function, :binding_function
          lower_function_call(callee, arguments)
        when :new, :binding_new then lower_constructor(callee, arguments, type)
        when :user_method, :binding_method, :binding_printf then lower_method_call(receiver, callee, arguments)
        when :binding_payload then lower_payload_call(receiver, callee, arguments)
        end
      end

      def lower_nil_predicate(receiver)
        statements, expression = lower_expression(receiver)
        [statements, @lir.create_unary("!", @value_layout.tag_of(expression), :bool)]
      end

      def lower_operator(receiver, callee, arguments, type)
        receiver_statements, receiver_expression = lower_expression(receiver)
        operator = OPERATOR_TEXT.fetch(callee[:name])
        if arguments.empty?
          return [receiver_statements, @lir.create_unary(operator, receiver_expression, @value_layout.type_of(type))]
        end

        argument_statements, argument_expressions = lower_arguments(arguments)
        [receiver_statements + argument_statements,
         @lir.create_binary(operator, receiver_expression, argument_expressions.first, @value_layout.type_of(type))]
      end

      def lower_function_call(callee, arguments)
        statements, expressions = lower_arguments(arguments)
        [statements, @lir.create_call(callee[:function], expressions, @value_layout.value_type_of(callee[:return_type]))]
      end

      # An object written anywhere other than the right of an assignment still needs storage
      # to be constructed into, so it gets a temporary of its own.
      def lower_constructor(callee, arguments, type)
        struct = @value_layout.type_of(type)
        instance_name = @function_scope.next_temporary
        place = @lir.create_local(instance_name, struct)

        initialized = @lir.create_brace_init([], struct)
        [[@lir.create_declare(instance_name, struct, initialized)] + construction_of(place, callee, arguments), place]
      end

      def construction_of(place, callee, arguments)
        argument_statements, argument_expressions = lower_arguments(arguments)
        initializer = @lir.create_call(callee[:function], [@lir.reference_to(place)] + argument_expressions, :void)

        argument_statements + [@lir.create_expression(initializer)]
      end

      def lower_method_call(receiver, callee, arguments)
        receiver_statements, receiver_expression = receiver ? lower_expression(receiver) : [[], nil]
        self_argument = receiver_expression ? @lir.reference_to(receiver_expression) : @lir.create_self_pointer(@function_scope.self_type)
        argument_statements, argument_expressions = lower_arguments(arguments)

        [receiver_statements + argument_statements,
         @lir.create_call(callee[:function], [self_argument] + argument_expressions,
                          @value_layout.value_type_of(callee[:return_type]))]
      end

      # **A call that sends bytes sends one pointer and one length**, however many values
      # of whatever kinds the program listed: they become one string in the region first,
      # so that the binding sees one transaction rather than a list. Where they begin, and
      # whether the region is also handed over for what comes back, are both read off the
      # declaration — this side recognises no class here.
      def lower_payload_call(receiver, callee, arguments)
        signature = Peripheral[callee[:owner]].method_signature(callee[:name])
        receiver_statements, receiver_expression = lower_expression(receiver)
        arena, *written = arguments
        arena_statements, arena_expression = lower_expression(arena)
        given_statements, given_expressions = lower_arguments(written[0...signature[:payload_from]])
        sent_statements, sent_bytes, sent_length =
          payload.flattened(@lir.reference_to(arena_expression), written[signature[:payload_from]..]) do |one|
            lower_expression(one)
          end

        binding_arguments = [@lir.reference_to(receiver_expression)]
        binding_arguments << @lir.reference_to(arena_expression) if signature[:return_type] == :arena_string
        binding_arguments += given_expressions + [sent_bytes, sent_length]

        [receiver_statements + arena_statements + given_statements + sent_statements,
         @lir.create_call(
           callee[:function], binding_arguments, @value_layout.value_type_of(callee[:return_type])
         )]
      end

      def payload = BytesSent.new(@lir, @tast, @value_layout, @function_scope)

      def arena_storage = ArenaStorage.new(@lir, @function_scope, @value_layout)

      def lower_arguments(arguments)
        statements = []
        expressions = arguments.map do |argument|
          argument_statements, expression = lower_expression(argument)
          statements.concat(argument_statements)
          @binding_storage.rvalue(argument, expression)
        end
        [statements, expressions]
      end

      def place_of(binding, type)
        if binding[:kind] == :local
          @lir.create_local(binding[:name], type)
        else
          self_pointer = @lir.create_self_pointer(@function_scope.self_type)
          @lir.create_field_access(self_pointer, @value_layout.field_name(binding[:name]), type)
        end
      end

      # Must agree with the name the type inferrer put in the callee.
      def function_name(owner, name)
        :"#{owner}_#{name.to_s.sub(/\?\z/, '_p').sub(/!\z/, '_bang').sub(/=\z/, '_set')}"
      end
    end
  end
end
