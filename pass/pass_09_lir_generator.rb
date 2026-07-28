# frozen_string_literal: true

require_relative "../ir/lir"

module BareRubyProt
  module Pass
    class LirGenerator
      OPERATOR_TEXT = {
        :+ => "+", :- => "-", :* => "*", :/ => "/", :% => "%",
        :<< => "<<", :>> => ">>", :& => "&", :| => "|", :^ => "^",
        :== => "==", :!= => "!=", :< => "<", :<= => "<=", :> => ">", :>= => ">=",
        :-@ => "-", :~ => "~", :! => "!"
      }.freeze
      ARENA_STRUCT = :bareruby_arena_t
      ARENA_SCOPE_STRUCT = :bareruby_arena_scope
      STRING_STRUCT = :bareruby_string_t
      FunctionState = Struct.new(
        :declared, :pointer_locals, :temp_index, :arena_index, :self_type, :return_type, :void_return,
        keyword_init: true
      )

      attr_reader :result

      def initialize(typed_ast)
        @tast = typed_ast
        @lir = LIR.new
      end

      def run
        structs = []
        functions = []
        @interrupt_functions = []
        @array_structs = {}
        @nilable_structs = {}

        @tast.program_body.each do |statement|
          next unless class_definition?(statement)

          name, ivars, methods = @tast.children_of(statement)
          @storage_ivars = owning_ivars(methods)
          fields = ivars.map { |ivar| @lir.create_field(field_name(ivar[:name]), ivar_type(ivar)) }
          structs << @lir.create_struct(name, fields)
          methods.each { |method| functions << lower_method(method) }
        end

        functions << lower_main
        functions.concat(@interrupt_functions)
        @result = @lir.replace_module(@nilable_structs.values + @array_structs.values + structs, functions)

        self
      end

      def class_definition?(node) = @tast.node_type(node) == :class_definition

      def lower_method(node)
        identity, parameters, body = @tast.children_of(node)
        with_function(identity[:owner], identity[:return_type]) do
          lir_parameters = [{ name: :self, type: function_state.self_type }]
          parameters.each do |parameter|
            binding, type = @tast.children_of(parameter)
            function_state.declared << binding[:name]
            function_state.pointer_locals << binding[:name] if shared_type?(type)
            lir_parameters << { name: binding[:name], type: binding_type(binding, type) }
          end

          statements = predeclare_nilable_locals(body) + body.flat_map { |statement| lower_statement(statement) }
          @lir.create_function(
            function_name(identity[:owner], identity[:name]),
            lir_parameters,
            value_lir_type(identity[:return_type]),
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
        previous_state = @function_state
        @function_state = FunctionState.new(
          declared: [], pointer_locals: [], temp_index: 0, arena_index: 0,
          self_type: self_class && @lir.pointer_type(@lir.struct_type(self_class)),
          return_type:, void_return: lir_type(return_type) == :void
        )
        yield
      ensure
        @function_state = previous_state
      end

      def function_state = @function_state

      def lower_interrupt(node)
        receiver, events, block, = @tast.children_of(node)
        handler_name = :"bareruby_interrupt_handler_#{@interrupt_functions.length}"
        parameters, body, = @tast.children_of(block)
        raise "GPIO#on_interrupt requires a zero-argument block" unless parameters.empty?

        receiver_statements, receiver_expression = lower_expression(receiver)
        events_statements, events_expression = lower_expression(events)
        @interrupt_functions << with_function(nil, :Nil) {
          statements = predeclare_nilable_locals(body) + body.flat_map { |statement| lower_statement(statement) }
          @lir.create_function(handler_name, [], :void, statements + [@lir.create_return(nil)], context: :realtime)
        }

        receiver_statements + events_statements + [@lir.create_expression(
          @lir.create_call(
            :bareruby_gpio_on_interrupt,
            [reference_to(receiver_expression), events_expression, @lir.create_function_reference(handler_name)], :void
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
          next if function_state.declared.include?(binding[:name])

          function_state.declared << binding[:name]
          type = binding[:type]
          @lir.create_declare(binding[:name], lir_type(type), nilable_absent(type))
        end
      end

      def collect_nilable_bindings(value, bindings)
        return value.each { |element| collect_nilable_bindings(element, bindings) } if value.is_a?(Array)
        return unless value.is_a?(Hash) && value.key?(:children)
        return if @tast.node_type(value) == :arena

        if @tast.node_type(value) == :assignment
          binding = @tast.children_of(value)[0]
          bindings[binding[:name]] = binding if binding[:kind] == :local && nilable_type?(binding[:type])
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
        return lower_statement(value) + [@lir.create_return(nil)] if function_state.void_return

        statements, expression = lower_expression(value)
        statements + [@lir.create_return(coerce_value(value, expression, function_state.return_type))]
      end

      def lower_for_range(node)
        binding, type, start_value, limit_value, inclusive, body = @tast.children_of(node)
        element_type = lir_type(type)
        start_statements, start_expression = lower_expression(start_value)
        limit_statements, limit_expression = lower_expression(limit_value)
        limit_name = next_temp

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
        binding, size, body = @tast.children_of(node)
        index = next_arena_index
        struct = @lir.struct_type(ARENA_STRUCT)
        place = @lir.create_local(binding[:name], struct)
        function_state.declared << binding[:name]
        scope_struct = @lir.struct_type(ARENA_SCOPE_STRUCT)

        opening = [@lir.create_declare(binding[:name], struct, nil)] + arena_setup(place, size, index) +
                  [@lir.create_declare(
                    :"arena_scope_#{index}", scope_struct,
                    @lir.create_brace_init([@lir.create_address_of(place)], scope_struct)
                  )]
        [@lir.create_scope(opening + lower_block_body(body))]
      end

      # A local the block introduces does not exist after it, in Ruby or in the C++ scope
      # the block becomes, so what was declared inside is forgotten on the way out and the
      # next block is free to use the same names.
      def lower_block_body(body)
        declared = function_state.declared.dup
        pointers = function_state.pointer_locals.dup
        statements = predeclare_nilable_locals(body) + lower_body(body)
        function_state.declared = declared
        function_state.pointer_locals = pointers
        statements
      end

      # A long-lived arena outlives no scope, so it takes no guard: reset is the only
      # thing that releases it.
      def lower_arena_new(node)
        size, type = @tast.children_of(node)
        struct = lir_type(type)
        name = next_temp
        place = @lir.create_local(name, struct)
        [[@lir.create_declare(name, struct, nil)] + arena_setup(place, size, next_arena_index), place]
      end

      # A creation expression is where the region comes from, so the binding it is
      # assigned to holds the arena itself rather than a pointer to one.
      def lower_arena_assignment(binding, value, type)
        struct = lir_type(type)
        place = place_of(binding, struct)
        [storage_declaration(binding, struct) +
          arena_setup(place, @tast.children_of(value)[0], next_arena_index), place]
      end

      def arena_setup(place, size, index)
        storage = :"arena_storage_#{index}"
        initializer = @lir.create_call(
          :bareruby_arena_init,
          [reference_to(place),
           @lir.create_local(storage, @lir.pointer_type(:uint8)),
           @lir.create_const_int(size, :int32)],
          :void
        )
        [@lir.create_declare_arena_storage(storage, size), @lir.create_expression(initializer)]
      end

      # The length is bound to a local first, because the handle stores it as well as
      # allocating from it and the expression it came from may not be evaluated twice.
      def lower_arena_alloc(node)
        receiver, length, type = @tast.children_of(node)
        struct = lir_type(type)
        element = lir_type(type[:element])
        receiver_statements, receiver_expression = lower_expression(receiver)
        length_statements, length_expression = lower_expression(length)
        length_name = next_temp
        name = next_temp
        length_local = @lir.create_local(length_name, :int32)
        place = @lir.create_local(name, struct)

        statements = receiver_statements + length_statements +
                     [@lir.create_declare(length_name, :int32, length_expression),
                      @lir.create_declare(name, struct, nil),
                      @lir.create_assign(items_of(place), allocation_of(receiver_expression, length_local, element)),
                      @lir.create_assign(length_of(place), length_local)]
        [statements, place]
      end

      def allocation_of(arena_expression, length_local, element)
        bytes = @lir.create_binary("*", length_local, @lir.create_size_of(element, :int32), :int32)
        call = @lir.create_call(
          :bareruby_arena_alloc,
          [reference_to(arena_expression), bytes],
          @lir.pointer_type(:void)
        )
        @lir.create_cast(call, @lir.pointer_type(element))
      end

      def lower_arena_length(node)
        statements, expression = lower_expression(@tast.children_of(node)[0])
        [statements, length_of(expression)]
      end

      def length_of(base) = @lir.create_field_access(base, :length, :int32)

      # Only Bool can be false, so a condition of any other
      # type is statically true and the test disappears.
      def lower_condition(node)
        statements, expression = lower_expression(node)
        type = @tast.value_type(node)
        return [statements, expression] if type == :Bool
        return [statements, @lir.create_const_bool(false)] if type == :Nil
        return [statements, nilable_truth(expression, type)] if nilable_type?(type)

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
          [[], @lir.create_const_int(value, lir_type(type))]
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
        when :arena_new
          lower_arena_new(node)
        when :arena_alloc
          lower_arena_alloc(node)
        when :arena_length
          lower_arena_length(node)
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
        return lower_nilable_logical(operator, left, right, type) if nilable_type?(@tast.value_type(left))

        left_statements, left_expression = lower_expression(left)
        right_statements, right_expression = lower_expression(right)
        [left_statements + right_statements,
         @lir.create_binary(operator == :and ? "&&" : "||", left_expression, right_expression, lir_type(type))]
      end

      def lower_nilable_logical(operator, left, right, type)
        left_statements, left_expression = lower_expression(left)
        left_type = @tast.value_type(left)
        left_name = next_temp
        left_local_type = value_lir_type(left_type)
        left_local = @lir.create_local(left_name, left_local_type)
        result_name = next_temp
        result_type = value_lir_type(type)
        result = @lir.create_local(result_name, result_type)
        statements = left_statements + [
          @lir.create_declare(left_name, left_local_type, left_expression),
          @lir.create_declare(result_name, result_type, nil)
        ]

        if operator == :or
          present = @lir.create_assign(result, nilable_value(left_local, left_type))
          absent = lower_expression_into(right, result, type)
        else
          present = lower_expression_into(right, result, type)
          absent = [@lir.create_assign(result, nilable_absent(type))]
        end
        statements << @lir.create_if(nilable_truth(left_local, left_type), [present].flatten, absent)
        [statements, result]
      end

      # An if used as a value becomes a declaration plus branches that assign into it.
      def lower_if_expression(node)
        condition, then_body, else_body, type = @tast.children_of(node)
        result_type = value_lir_type(type)
        result_name = next_temp
        condition_statements, condition_expression = lower_condition(condition)

        statements = condition_statements + [@lir.create_declare(result_name, result_type, nil)]
        statements << @lir.create_if(
          condition_expression,
          lower_body_into(then_body, result_name, type),
          else_body ? lower_body_into(else_body, result_name, type) :
            [@lir.create_assign(@lir.create_local(result_name, result_type), nilable_absent(type))]
        )
        [statements, @lir.create_local(result_name, result_type)]
      end

      def lower_body_into(statements, result_name, type)
        result_type = value_lir_type(type)
        return [@lir.create_assign(@lir.create_local(result_name, result_type), nilable_absent(type))] if statements.empty?

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
        function_state.declared << binding[:name]

        call = @lir.create_call(
          :bareruby_format,
          [place, @lir.create_const_int(capacity, :int32), format_expression] + argument_expressions,
          :void
        )
        [[@lir.create_declare_buffer(binding[:name], capacity)] + statements + argument_statements +
          [@lir.create_expression(call)], place]
      end

      def items_of(base) = @lir.create_field_access(base, :items, nil)

      # Indexing is pointer arithmetic and carries no range test, so the index lowers to
      # whatever expression it is.
      def lower_index(node)
        receiver, index, type = @tast.children_of(node)
        receiver_statements, receiver_expression = lower_expression(receiver)
        index_statements, index_expression = lower_expression(index)
        [receiver_statements + index_statements,
         @lir.create_index(items_of(receiver_expression), index_expression, lir_type(type))]
      end

      def lower_index_assign(node)
        receiver, index, value, type = @tast.children_of(node)
        receiver_statements, receiver_expression = lower_expression(receiver)
        index_statements, index_expression = lower_expression(index)
        value_statements, value_expression = lower_expression(value)
        place = @lir.create_index(items_of(receiver_expression), index_expression, lir_type(type))

        [receiver_statements + index_statements + value_statements +
          [@lir.create_assign(place, value_expression)], place]
      end

      def lower_assignment(node)
        binding, value, type = @tast.children_of(node)
        return lower_format_assignment(binding, value) if @tast.node_type(value) == :format
        storage_type = binding[:type] || type
        unless nilable_type?(storage_type)
          return lower_array_assignment(binding, value, type) if array_creation?(value)
          return lower_arena_assignment(binding, value, type) if arena_creation?(value)
          return lower_object_assignment(binding, value, type) if object_creation?(value)
        end

        statements, value_expression = lower_expression(value)
        function_state.pointer_locals << binding[:name] if shared_type?(type) && binding[:kind] == :local
        value_expression = coerce_value(value, value_expression, storage_type)
        place = place_of(binding, binding_type(binding, storage_type))

        if binding[:kind] == :local && !function_state.declared.include?(binding[:name])
          function_state.declared << binding[:name]
          written = statements + [
            @lir.create_declare(binding[:name], binding_type(binding, storage_type), value_expression)
          ]
        else
          written = statements + [@lir.create_assign(place, value_expression)]
        end
        [written, read_nilable_place(place, storage_type, type)]
      end

      def lower_reference(node)
        binding, type = @tast.children_of(node)
        storage_type = nilable_type?(binding[:type]) ? binding[:type] : type
        place = place_of(binding, binding_type(binding, storage_type))
        [[], read_nilable_place(place, storage_type, type)]
      end

      def read_nilable_place(place, storage_type, flow_type)
        return place unless nilable_type?(storage_type) && !nilable_type?(flow_type)

        nilable_value(place, storage_type)
      end

      def coerce_value(node, expression, target_type)
        source_type = @tast.value_type(node)
        return nilable_absent(target_type) if nilable_type?(target_type) && source_type == :Nil
        if nilable_type?(target_type) && !nilable_type?(source_type)
          return @lir.create_brace_init(
            [@lir.create_const_bool(true), shared_rvalue(node, expression)], lir_type(target_type)
          )
        end

        shared_rvalue(node, expression)
      end

      # Every object is shared, which is what Ruby does. Assignment names the same object
      # rather than copying it, so only the binding a creation expression is assigned to owns
      # storage and every other binding of that type is a pointer to somebody else's. Passing
      # an object to a method is that same assignment: a method that changes what it was
      # handed changes the caller's object, where a copy would take every change with it when
      # the call dropped it. An arena has a second reason — what it hands out is recorded in
      # the arena itself, so a method that allocated from a copy would leave the caller's
      # arena believing the room is still free.
      def instance_type?(type) = type.is_a?(Hash) && type[:kind] == :instance

      def array_type?(type) = type.is_a?(Hash) && type[:kind] == :array

      def shared_type?(type) = instance_type?(type) || array_type?(type)

      def nilable_type?(type) = type.is_a?(Hash) && type[:kind] == :nilable

      # A shared value in value position is always a reference: returning one by value
      # would copy it, and nothing but dup copies an object.
      def value_lir_type(type)
        shared_type?(type) ? @lir.pointer_type(lir_type(type)) : lir_type(type)
      end

      def array_creation?(node) = %i[array array_fill array_dup].include?(@tast.node_type(node))

      def arena_creation?(node) = @tast.node_type(node) == :arena_new

      def object_creation?(node)
        @tast.node_type(node) == :call && %i[new binding_new].include?(@tast.children_of(node)[1][:kind])
      end

      def creation?(node) = array_creation?(node) || arena_creation?(node) || object_creation?(node)

      def owning_ivars(methods)
        names = []
        each_assignment(methods) do |binding, value|
          names << binding[:name] if binding[:kind] == :instance && creation?(value)
        end
        names
      end

      def each_assignment(value, &block)
        return value.each { |element| each_assignment(element, &block) } if value.is_a?(Array)
        return unless value.is_a?(Hash) && value.key?(:children)

        yield(value[:children][0], value[:children][1]) if value[:type] == :assignment
        each_assignment(value[:children], &block)
      end

      def ivar_type(ivar)
        binding_type({ kind: :instance, name: ivar[:name] }, ivar[:type])
      end

      def binding_type(binding, type)
        return lir_type(type) unless shared_type?(type)

        pointer_binding?(binding) ? @lir.pointer_type(lir_type(type)) : lir_type(type)
      end

      def pointer_binding?(binding)
        return !@storage_ivars.include?(binding[:name]) if binding[:kind] == :instance

        function_state.pointer_locals.include?(binding[:name])
      end

      # A shared value in value position is its address, so storage has to be taken the
      # address of and a pointer is already one.
      def shared_rvalue(node, expression)
        return expression unless shared_type?(@tast.value_type(node))

        reference_to(expression)
      end

      def reference_to(expression)
        pointer_expression?(expression) ? expression : @lir.create_address_of(expression)
      end

      def pointer_expression?(expression)
        type = @lir.value_type(expression)
        type.is_a?(Hash) && type[:kind] == :pointer
      end

      # A creation expression is where storage comes from, so the binding it is assigned to
      # holds the array itself rather than a pointer to one.
      def lower_array_assignment(binding, value, type)
        struct = lir_type(type)
        place = place_of(binding, struct)
        [storage_declaration(binding, struct) + fill_of(place, value, type), place]
      end

      # The same for an object: the binding a constructor is assigned to holds the instance,
      # and the constructor writes straight into it rather than into a temporary that would
      # then have to be copied there.
      def lower_object_assignment(binding, value, type)
        _receiver, callee, arguments, = @tast.children_of(value)
        struct = lir_type(type)
        place = place_of(binding, struct)
        [object_storage_declaration(binding, struct) + construction_of(place, callee, arguments), place]
      end

      # A local that owns storage is declared here rather than initialised from somewhere
      # else; an instance variable that owns storage is a field and is declared with the struct.
      def storage_declaration(binding, struct)
        return [] unless binding[:kind] == :local && !function_state.declared.include?(binding[:name])

        function_state.declared << binding[:name]
        [@lir.create_declare(binding[:name], struct, nil)]
      end

      def object_storage_declaration(binding, struct)
        return [] unless binding[:kind] == :local && !function_state.declared.include?(binding[:name])

        function_state.declared << binding[:name]
        [@lir.create_declare(binding[:name], struct, @lir.create_brace_init([], struct))]
      end

      # An array written anywhere other than the right of an assignment still needs
      # storage to fill, so it gets a temporary of its own.
      def lower_array_temporary(node)
        type = @tast.value_type(node)
        struct = lir_type(type)
        place = @lir.create_local(next_temp, struct)
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
        struct = lir_type(type)
        statements, expression = lower_expression(receiver)
        source = pointer_expression?(expression) ? @lir.create_unary("*", expression, struct) : expression
        statements + [@lir.create_assign(place, source)]
      end

      def fill_from_elements(place, value)
        elements, = @tast.children_of(value)
        elements.each_with_index.flat_map do |element, position|
          element_statements, element_expression = lower_expression(element)
          slot = @lir.create_index(
            items_of(place), @lir.create_const_int(position, :int32), @lir.value_type(element_expression)
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

        element_type = lir_type(type[:element])
        statements, expression = lower_expression(fill_value)
        source = next_temp
        counter = next_temp
        local = @lir.create_local(counter, :int32)

        statements + [@lir.create_declare(source, element_type, expression),
                      @lir.create_for(
                        @lir.create_declare(counter, :int32, @lir.create_const_int(0, :int32)),
                        @lir.create_binary("<", local, @lir.create_const_int(type[:capacity], :int32), :bool),
                        @lir.create_assign(local, @lir.create_binary("+", local, @lir.create_const_int(1, :int32), :int32)),
                        [@lir.create_assign(
                          @lir.create_index(items_of(place), local, element_type),
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
        when :binding_i2c then lower_i2c_call(receiver, callee, arguments)
        end
      end

      def lower_nil_predicate(receiver)
        statements, expression = lower_expression(receiver)
        [statements, @lir.create_unary("!", nilable_tag(expression), :bool)]
      end

      def lower_operator(receiver, callee, arguments, type)
        receiver_statements, receiver_expression = lower_expression(receiver)
        operator = OPERATOR_TEXT.fetch(callee[:name])
        return [receiver_statements, @lir.create_unary(operator, receiver_expression, lir_type(type))] if arguments.empty?

        argument_statements, argument_expressions = lower_arguments(arguments)
        [receiver_statements + argument_statements,
         @lir.create_binary(operator, receiver_expression, argument_expressions.first, lir_type(type))]
      end

      def lower_function_call(callee, arguments)
        statements, expressions = lower_arguments(arguments)
        [statements, @lir.create_call(callee[:function], expressions, value_lir_type(callee[:return_type]))]
      end

      # An object written anywhere other than the right of an assignment still needs storage
      # to be constructed into, so it gets a temporary of its own.
      def lower_constructor(callee, arguments, type)
        struct = lir_type(type)
        instance_name = next_temp
        place = @lir.create_local(instance_name, struct)

        initialized = @lir.create_brace_init([], struct)
        [[@lir.create_declare(instance_name, struct, initialized)] + construction_of(place, callee, arguments), place]
      end

      def construction_of(place, callee, arguments)
        argument_statements, argument_expressions = lower_arguments(arguments)
        initializer = @lir.create_call(callee[:function], [reference_to(place)] + argument_expressions, :void)

        argument_statements + [@lir.create_expression(initializer)]
      end

      def lower_method_call(receiver, callee, arguments)
        receiver_statements, receiver_expression = receiver ? lower_expression(receiver) : [[], nil]
        self_argument = receiver_expression ? reference_to(receiver_expression) : @lir.create_self_pointer(function_state.self_type)
        argument_statements, argument_expressions = lower_arguments(arguments)

        [receiver_statements + argument_statements,
         @lir.create_call(callee[:function], [self_argument] + argument_expressions,
                          value_lir_type(callee[:return_type]))]
      end

      # I2C's heterogeneous outputs become one arena string first, so the binding sees
      # one byte pointer and one length and can keep the whole write in one transaction.
      def lower_i2c_call(receiver, callee, arguments)
        receiver_statements, receiver_expression = lower_expression(receiver)
        arena, address, *rest = arguments
        arena_statements, arena_expression = lower_expression(arena)
        address_statements, address_expression = lower_expression(address)

        if callee[:name] == :read
          length, *outputs = rest
          length_statements, length_expression = lower_expression(length)
        else
          outputs = rest
          length_statements = []
        end

        output_statements, output_bytes, output_length =
          lower_i2c_outputs(arena_expression, outputs)
        binding_arguments = [reference_to(receiver_expression)]
        if callee[:name] == :read
          binding_arguments += [
            reference_to(arena_expression), address_expression, length_expression,
            output_bytes, output_length
          ]
        else
          binding_arguments += [address_expression, output_bytes, output_length]
        end

        statements = receiver_statements + arena_statements + address_statements +
                     length_statements + output_statements
        [statements, @lir.create_call(
          callee[:function], binding_arguments, value_lir_type(callee[:return_type])
        )]
      end

      def lower_i2c_outputs(arena_expression, outputs)
        return [[], @lir.create_const_string(""), @lir.create_const_int(0, :int32)] if outputs.empty?

        name = next_temp
        buffer = @lir.create_local(name, arena_string_lir_type)
        create = @lir.create_call(
          :bareruby_string_new,
          [reference_to(arena_expression), @lir.create_const_string("")],
          arena_string_lir_type
        )
        statements = [@lir.create_declare(name, arena_string_lir_type, create)]
        outputs.each { |output| statements.concat(lower_i2c_output(buffer, output)) }

        bytes = @lir.create_call(:bareruby_string_bytes, [buffer], :string_ptr)
        length = @lir.create_call(:bareruby_string_length, [buffer], :int32)
        [statements, bytes, length]
      end

      def lower_i2c_output(buffer, output)
        type = @tast.value_type(output)
        statements, expression = lower_expression(output)

        if type.is_a?(Symbol) && type.to_s.start_with?("Int")
          append = @lir.create_call(:bareruby_string_append_byte, [buffer, expression], arena_string_lir_type)
          return statements + [@lir.create_expression(append)]
        end

        if type == :String
          function = :bareruby_string_append
          arguments = [buffer, expression]
          if @tast.node_type(output) == :string
            function = :bareruby_string_append_bytes
            arguments << @lir.create_const_int(@tast.children_of(output)[0].bytesize, :int32)
          end
          append = @lir.create_call(function, arguments, arena_string_lir_type)
          return statements + [@lir.create_expression(append)]
        end

        if type.is_a?(Hash) && type[:kind] == :arena_string
          bytes = @lir.create_call(:bareruby_string_bytes, [expression], :string_ptr)
          length = @lir.create_call(:bareruby_string_length, [expression], :int32)
          append = @lir.create_call(
            :bareruby_string_append_bytes, [buffer, bytes, length], arena_string_lir_type
          )
          return statements + [@lir.create_expression(append)]
        end

        lower_i2c_array_output(buffer, type, statements, expression)
      end

      def lower_i2c_array_output(buffer, type, statements, expression)
        counter = next_temp
        local = @lir.create_local(counter, :int32)
        limit = if type[:kind] == :array
                  @lir.create_const_int(type[:capacity], :int32)
                else
                  length_of(expression)
                end
        element = @lir.create_index(items_of(expression), local, lir_type(type[:element]))
        append = @lir.create_call(
          :bareruby_string_append_byte, [buffer, element], arena_string_lir_type
        )
        loop = @lir.create_for(
          @lir.create_declare(counter, :int32, @lir.create_const_int(0, :int32)),
          @lir.create_binary("<", local, limit, :bool),
          @lir.create_assign(
            local, @lir.create_binary("+", local, @lir.create_const_int(1, :int32), :int32)
          ),
          [@lir.create_expression(append)]
        )
        statements + [loop]
      end

      def lower_arguments(arguments)
        statements = []
        expressions = arguments.map do |argument|
          argument_statements, expression = lower_expression(argument)
          statements.concat(argument_statements)
          shared_rvalue(argument, expression)
        end
        [statements, expressions]
      end

      def place_of(binding, type)
        if binding[:kind] == :local
          @lir.create_local(binding[:name], type)
        else
          @lir.create_field_access(@lir.create_self_pointer(function_state.self_type), field_name(binding[:name]), type)
        end
      end

      def lir_type(type)
        case type
        when :Int8, :Int16, :Int32 then :int32
        when :Int64 then :int64
        when :Bool then :bool
        when :Fixed then :fixed
        when :String then :string_ptr
        when Hash then struct_lir_type(type)
        else :void
        end
      end

      def struct_lir_type(type)
        case type[:kind]
        when :array then array_struct_type(type)
        when :arena_array then arena_array_struct_type(type)
        when :arena_string then arena_string_lir_type
        when :nilable then nilable_struct_type(type)
        else @lir.struct_type(type[:struct] || type[:class_name])
        end
      end

      # T? is deliberately uniform: one explicit tag followed by the ordinary value
      # representation. No pointer niche or target-specific sentinel is involved.
      def nilable_struct_type(type)
        inner = type[:inner]
        name = :"bareruby_nilable_#{nilable_type_name(inner)}_t"
        @nilable_structs[name] ||= @lir.create_struct(
          name,
          [@lir.create_field(:tag, :bool), @lir.create_field(:value, value_lir_type(inner))]
        )
        @lir.struct_type(name)
      end

      def nilable_type_name(type)
        return type.to_s.downcase if type.is_a?(Symbol)
        return "arena_string" if type[:kind] == :arena_string
        return "array_#{type[:capacity]}" if type[:kind] == :array
        return type[:class_name].to_s.downcase if type[:kind] == :instance

        type[:kind].to_s
      end

      def nilable_absent(type)
        inner = type[:inner]
        @lir.create_brace_init(
          [@lir.create_const_bool(false), zero_value(value_lir_type(inner))], lir_type(type)
        )
      end

      def zero_value(type)
        return @lir.create_const_bool(false) if type == :bool
        return @lir.create_brace_init([], type) if type.is_a?(Hash) && type[:kind] != :pointer

        @lir.create_const_int(0, type == :int64 ? :int64 : :int32)
      end

      def nilable_tag(expression) = @lir.create_field_access(expression, :tag, :bool)

      def nilable_truth(expression, type)
        tag = nilable_tag(expression)
        return tag unless type[:inner] == :Bool

        @lir.create_binary("&&", tag, nilable_value(expression, type), :bool)
      end

      def nilable_value(expression, type)
        @lir.create_field_access(expression, :value, value_lir_type(type[:inner]))
      end

      # A variable-length string is always the pointer the region handed out, never a
      # struct of its own: the handle lives in the region with the bytes, so a binding
      # holds the address of the one string rather than a copy of a handle whose length
      # the next append would leave behind. The runtime declares the struct, and nothing
      # here reads a field of it.
      def arena_string_lir_type = @lir.pointer_type(@lir.struct_type(STRING_STRUCT))

      # An array becomes a struct wrapping one C array so that dup is a plain assignment
      # and an owner can embed one inline. A raw C array would decay to a pointer.
      def array_struct_type(type)
        raise "the element type of this array was never determined" if type[:element].nil?

        element = lir_type(type[:element])
        name = :"bareruby_array_#{element}_#{type[:capacity]}_t"
        @array_structs[name] ||= @lir.create_struct(
          name, [@lir.create_field(:items, @lir.c_array_type(element, type[:capacity]))]
        )
        @lir.struct_type(name)
      end

      # An arena array is a pointer into the region plus the length that was asked for, so
      # assigning one shares the allocation the way assigning an array does, and the
      # capacity the compiler cannot know is carried at run time. That is why the handle
      # itself is not a shared type: both of its fields are settled when the allocation is
      # made and nothing afterwards changes them, so a copy of the handle still names the
      # same elements, and the method that allocated it can hand it back — where a pointer
      # to it would outlive the local it pointed at.
      def arena_array_struct_type(type)
        raise "the element type of this arena array was never determined" if type[:element].nil?

        element = lir_type(type[:element])
        name = :"bareruby_arena_array_#{element}_t"
        @array_structs[name] ||= @lir.create_struct(
          name, [@lir.create_field(:items, @lir.pointer_type(element)), @lir.create_field(:length, :int32)]
        )
        @lir.struct_type(name)
      end

      def field_name(name) = name.to_s.delete_prefix("@").to_sym

      # Must agree with the name the type inferrer put in the callee.
      def function_name(owner, name)
        :"#{owner}_#{name.to_s.sub(/\?\z/, '_p').sub(/!\z/, '_bang').sub(/=\z/, '_set')}"
      end

      def next_temp
        function_state.temp_index += 1
        :"temporary_#{function_state.temp_index}"
      end

      def next_arena_index
        function_state.arena_index += 1
      end
    end
  end
end
