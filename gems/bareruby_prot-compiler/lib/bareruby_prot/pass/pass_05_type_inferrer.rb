# frozen_string_literal: true

require_relative "../ir/typed_ast"
require_relative "pass_05_type_inferrer/class_definition"
require "bareruby_prot/peripheral"
require_relative "pass_05_type_inferrer/binding_function"
require_relative "pass_05_type_inferrer/type_union"
require_relative "pass_05_type_inferrer/type_environment"
require_relative "pass_05_type_inferrer/fixed"
require_relative "pass_05_type_inferrer/printf_format"
require_relative "pass_05_type_inferrer/arena"
require_relative "pass_05_type_inferrer/arena_string"
require_relative "pass_05_type_inferrer/string_view"
require_relative "pass_05_type_inferrer/arena_array"

module BareRubyProt
  module Pass
    class TypeInferrer
      RECEIVER_ITERATOR_NAMES = %i[times upto].freeze
      SIZE_NAMES = %i[size length].freeze
      # The two that take an index. A name that is none of an array's own used to be
      # treated as one of these, which turned a method it does not have into a crash
      # somewhere below rather than a sentence about the array.
      INDEX_NAMES = %i[[] []=].freeze
      UNARY_OPERATORS = %i[-@ ~].freeze
      BINARY_OPERATORS = %i[+ - * / % << >> & | ^].freeze
      COMPARISON_OPERATORS = %i[== != < <= > >=].freeze


      attr_reader :result

      def initialize(bareruby_ast)
        @bareruby_ast = bareruby_ast
        @tast = TypedAST.new
        @classes = {}
        @current_method = nil
        @initializing = false
        @arena = nil
      end

      def run
        @rescues_present = contains_begin?(@bareruby_ast.program_body)
        @constant_locals = collect_constant_locals
        @classes = ClassDefinition.declared_in(@bareruby_ast.program_body, @bareruby_ast)

        @local_bindings = {}
        type_environment = TypeEnvironment.new(@tast)
        typed = @bareruby_ast.program_body.map do |statement|
          definition?(statement) ? statement : infer_node(statement, type_environment:)
        end

        # A class opened twice is emitted once: the second opening added its definitions
        # to the same class, and they are all in the first one already.
        emitted = []
        body = @bareruby_ast.program_body.zip(typed).filter_map do |original, typed_statement|
          next if module_definition?(original)
          next typed_statement unless class_definition?(original)

          name, = @bareruby_ast.children_of(original)
          next if emitted.include?(name)

          emitted << name
          build_class_definition(original)
        end

        @result = @tast.replace_program(body)

        self
      end

      def contains_begin?(value)
        return value.any? { |element| contains_begin?(element) } if value.is_a?(Array)
        return false unless value.is_a?(Hash) && value.key?(:children)

        value[:type] == :begin || contains_begin?(value[:children])
      end

      # An array capacity may be written as a local that holds a literal, so the locals
      # assigned exactly once from an integer literal are collected up front. Requiring a
      # single assignment is what makes the value safe to use anywhere in the program,
      # including before the assignment has been walked.
      def collect_constant_locals
        assignments = Hash.new { |hash, name| hash[name] = [] }
        each_local_assignment(@bareruby_ast.program_body) { |name, value| assignments[name] << value }
        bound = parameter_names(@bareruby_ast.program_body)

        assignments.filter_map do |name, values|
          next if bound.include?(name)
          next unless values.one? && @bareruby_ast.node_type(values[0]) == :integer

          [name, @bareruby_ast.children_of(values[0])[0]]
        end.to_h
      end

      # Names are collected across the whole program rather than per scope, so a name that
      # is ever a parameter is dropped: its value comes from the caller, not the literal.
      def parameter_names(value, names = [])
        return value.each { |element| parameter_names(element, names) } && names if value.is_a?(Array)
        return names unless value.is_a?(Hash) && value.key?(:children)

        names << value[:children][0] if value[:type] == :parameter
        parameter_names(value[:children], names)
      end

      def each_local_assignment(value, &block)
        return value.each { |element| each_local_assignment(element, &block) } if value.is_a?(Array)
        return unless value.is_a?(Hash) && value.key?(:children)

        if value[:type] == :assignment
          kind, name = @bareruby_ast.children_of(value[:children][0])
          yield(name, value[:children][1]) if kind == :local
        end
        each_local_assignment(value[:children], &block)
      end

      def class_definition?(node) = @bareruby_ast.class_definition?(node)

      def module_definition?(node) = @bareruby_ast.module_definition?(node)

      def definition?(node) = class_definition?(node) || module_definition?(node)

      def method_named(class_name, name) = @classes.fetch(class_name).method_named(name)

      # Every definition the class flattened is emitted, including the ones a subclass
      # or a later include shadowed, because super still reaches them.
      def build_class_definition(node)
        name, = @bareruby_ast.children_of(node)
        class_definition = @classes.fetch(name)
        methods = class_definition.definitions.filter_map do |definition|
          build_method_definition(definition) unless peripheral_constructor?(name, definition)
        end
        @tast.create_class_definition(name, class_definition.ivars, methods, span_of(node))
      end

      # **A peripheral is constructed by the binding's own function**, so the empty
      # initialize every class is given has nothing to answer for here. Dropping it is
      # what keeps a program that names no UART from carrying one: the class arrives in
      # every program, and an initialize is the one definition that is inferred without
      # anybody calling it.
      def peripheral_constructor?(class_name, definition)
        definition.name == :initialize && Peripheral.known?(class_name)
      end

      def build_method_definition(method_info)
        return unless method_info.inferred?

        identity = @tast.create_identity(
          method_info.owner, method_info.qualified_name, method_info.parameter_types, method_info.return_type
        )
        typed_parameters = method_info.parameter_bindings.zip(method_info.parameters, method_info.parameter_types)
                                     .map { |binding, parameter, type| @tast.create_parameter(binding, type, span_of(parameter)) }
        @tast.create_method_definition(identity, typed_parameters, method_info.typed_body, nil)
      end

      # A shadowed definition needs a name of its own in the generated code.
      def resolve_method_call(method_info, argument_types)
        infer_method!(method_info, argument_types) unless method_info.inferred?
        method_info
      end

      def infer_method!(method_info, argument_types)
        enclosing_bindings = @local_bindings
        @local_bindings = {}
        bindings = method_info.parameters.each_with_index.map do |parameter, index|
          @tast.create_binding(:local, @bareruby_ast.children_of(parameter)[0], argument_types[index])
        end
        bindings.each { |binding| @local_bindings[binding[:name]] = binding }
        type_environment = TypeEnvironment.new(
          @tast, self_class: method_info.owner,
          bindings: bindings.each_with_index.to_h { |binding, index| [binding[:name], [binding, argument_types[index]]] }
        )
        # Recorded before the body is inferred, because a bare super inside it forwards
        # these very parameters.
        method_info.parameter_types = argument_types
        method_info.parameter_bindings = bindings

        enclosing = @current_method
        enclosing_initializing = @initializing
        @current_method = method_info
        # A method initialize calls is part of initialising: what it assigns is assigned
        # before the object is anyone else's to look at.
        @initializing = enclosing_initializing || method_info.name == :initialize
        typed_body = infer_body(method_info.body, type_environment:)
        finalize_initialize_ivars(method_info.owner, typed_body) if method_info.name == :initialize
        @initializing = enclosing_initializing
        @current_method = enclosing
        @local_bindings = enclosing_bindings

        method_info.typed_body = typed_body
        method_info.return_type =
          method_info.name == :initialize ? :Nil : method_return_type(typed_body)
      end

      # An instance starts with every field in its Nil state. Assignments guaranteed on
      # every path through initialize replace that state; every other field keeps the
      # Nil path and therefore has T? storage.
      def finalize_initialize_ivars(owner, typed_body)
        class_definition = @classes.fetch(owner)
        class_definition.note_initialized(definitely_assigned_ivars(typed_body))
        class_definition.nil_unless_initialized { |type| TypeUnion.of(@tast, :Nil, type) }
        class_definition.definitions.each do |definition|
          annotate_ivar_storage_types!(definition.typed_body, class_definition) if definition.typed_body
        end
        annotate_ivar_storage_types!(typed_body, class_definition)
      end

      def definitely_assigned_ivars(statements, assigned = [])
        statements.reduce(assigned.dup) do |current, statement|
          case @tast.node_type(statement)
          when :assignment
            binding = @tast.children_of(statement)[0]
            binding[:kind] == :instance ? current | [binding[:name]] : current
          when :if
            _condition, then_body, else_body, = @tast.children_of(statement)
            then_assigned = definitely_assigned_ivars(then_body, current)
            else_assigned = else_body ? definitely_assigned_ivars(else_body, current) : current
            then_assigned & else_assigned
          when :begin
            body, rescue_body = @tast.children_of(statement)
            definitely_assigned_ivars(body, current) & definitely_assigned_ivars(rescue_body, current)
          when :arena
            definitely_assigned_ivars(@tast.children_of(statement)[2], current)
          when :return
            value = @tast.children_of(statement)[0]
            value ? definitely_assigned_ivars([value], current) : current
          when :call
            definitely_assigned_by_call(statement, current)
          else
            current
          end
        end
      end

      # A call on self reaches the object's own method, and what that method assigns on
      # every one of its paths is assigned on this one.
      def definitely_assigned_by_call(statement, current)
        receiver, callee, = @tast.children_of(statement)
        return current unless receiver.nil? && callee[:kind] == :user_method

        definition = @classes.fetch(callee[:owner]).method_named(callee[:name])
        return current unless definition&.typed_body

        definitely_assigned_ivars(definition.typed_body, current)
      end

      def annotate_ivar_storage_types!(value, class_definition)
        return value.each { |element| annotate_ivar_storage_types!(element, class_definition) } if value.is_a?(Array)
        return unless value.is_a?(Hash) && value.key?(:children)

        if %i[assignment reference].include?(@tast.node_type(value))
          binding = @tast.children_of(value)[0]
          if binding[:kind] == :instance && class_definition.ivar?(binding[:name])
            binding[:type] = class_definition.ivar_type(binding[:name])
          end
        end
        annotate_ivar_storage_types!(value[:children], class_definition)
      end

      # Every return in the body contributes, plus the value the body falls off the end
      # with. NoReturn contributes nothing.
      def method_return_type(typed_body)
        return :Nil if typed_body.empty?

        types = collect_return_types(typed_body)
        types << @tast.value_type(typed_body.last) unless terminator?(typed_body.last)
        types = types.reject { |type| type == :NoReturn }
        types.empty? ? :Nil : types.reduce { |left, right| TypeUnion.of(@tast, left, right) }
      end

      def collect_return_types(statements)
        statements.flat_map do |statement|
          case @tast.node_type(statement)
          when :return
            value = @tast.children_of(statement)[0]
            [@tast.value_type(statement)] + (value ? collect_return_types([value]) : [])
          when :if
            _condition, then_body, else_body, = @tast.children_of(statement)
            collect_return_types(then_body) + collect_return_types(else_body || [])
          when :while
            collect_return_types(@tast.children_of(statement)[1])
          when :arena
            collect_return_types(@tast.children_of(statement)[2])
          when :call
            block = @tast.children_of(statement)[3]
            block ? collect_return_types(@tast.children_of(block)[1]) : []
          else []
          end
        end
      end

      def infer_body(statements, type_environment:)
        statements.map { |statement| infer_node(statement, type_environment:) }
      end

      def infer_node(node, type_environment:)
        case @bareruby_ast.node_type(node)
        when :integer then infer_integer(node)
        when :nil then @tast.create_nil(span_of(node))
        when :float then infer_float(node)
        when :boolean then infer_boolean(node)
        when :string then infer_string(node, type_environment:)
        when :symbol then infer_symbol(node)
        when :super then infer_super(node, type_environment:)
        when :begin then infer_begin(node, type_environment:)
        when :constant_path then infer_constant_path(node)
        when :if then infer_if(node, type_environment:)
        when :while then infer_while(node, type_environment:)
        when :logical then infer_logical(node, type_environment:)
        when :reference then infer_reference(node, type_environment:)
        when :assignment then infer_assignment(node, type_environment:)
        when :array then infer_array(node, type_environment:)
        when :call then infer_call(node, type_environment:)
        when :return then infer_return(node, type_environment:)
        when :iteration_control then infer_iteration_control(node)
        end
      end

      def infer_integer(node)
        value = @bareruby_ast.children_of(node)[0]
        @tast.create_integer(value, TypeUnion.literal(value), span_of(node))
      end

      def infer_boolean(node)
        @tast.create_boolean(@bareruby_ast.children_of(node)[0], :Bool, span_of(node))
      end

      # A decimal literal is rounded to the nearest representable Q16.16 value at compile
      # time and carried as its internal integer form.
      def infer_float(node)
        value = @bareruby_ast.children_of(node)[0]
        @tast.create_integer(Fixed.scaled(value), :Fixed, span_of(node))
      end

      # begin/rescue lowers to try/catch. Only the untyped rescue form is handled: an
      # exception class hierarchy is still undecided, so nothing here invents one.
      def infer_begin(node, type_environment:)
        body, rescue_body = @bareruby_ast.children_of(node)
        @tast.create_begin(
          infer_body(body, type_environment:), infer_body(rescue_body, type_environment:), span_of(node)
        )
      end

      # raise degrades to panic when the program has no begin at all, and throws
      # otherwise. Only the string form is accepted; the other forms are not settled.
      def infer_raise_call(arguments, type_environment:, span:)
        argument_tasts = arguments.map { |argument| text_of(argument, type_environment:) }
        function = @rescues_present ? :bareruby_throw : :bareruby_panic
        callee = @tast.create_callee(:builtin_function, nil, :raise, function, %i[String], :NoReturn)
        @tast.create_call(nil, callee, argument_tasts, nil, :NoReturn, span)
      end

      # super is a static call to the definition this one shadowed. No arguments means
      # forward the ones the method received.
      def infer_super(node, type_environment:)
        ancestor = @current_method.ancestor
        arguments = @bareruby_ast.children_of(node)[0]
        argument_tasts =
          if arguments.empty?
            @current_method.parameter_bindings.zip(@current_method.parameter_types)
                           .map { |binding, type| @tast.create_reference(binding, type, span_of(node)) }
          else
            arguments.map { |argument| infer_node(argument, type_environment:) }
          end

        resolved = resolve_method_call(ancestor, argument_types(argument_tasts))
        callee = @tast.create_callee(
          :user_method, resolved.owner, resolved.name,
          function_name(resolved.owner, resolved.qualified_name),
          resolved.parameter_types, resolved.return_type
        )
        @tast.create_call(nil, callee, argument_tasts, nil, resolved.return_type, span_of(node))
      end

      def infer_symbol(node)
        @tast.create_symbol(@bareruby_ast.children_of(node)[0], :Symbol, span_of(node))
      end

      # The element type is the least upper bound of the elements, so a literal that mixes
      # types with no common widening is an error here rather than something the backend
      # has to represent.
      # An empty literal inside a region is the growing array. It has no other use — a
      # fixed-capacity array of nothing holds nothing — so the form is free to mean the
      # one thing a program writes it for.
      def infer_array(node, type_environment:)
        elements = @bareruby_ast.children_of(node)[0]
        if elements.empty?
          raise "[] is the growing array and needs a region; write ::Array.new outside one" if @arena.nil?

          return infer_arena_array_new_call([], type_environment:, span: span_of(node))
        end

        elements = elements.map { |element| infer_node(element, type_environment:) }
        types = argument_types(elements)
        unless types.uniq.one? || types.all? { |element| TypeUnion::WIDTHS.include?(element) }
          raise "array literal mixes #{types.uniq.join(' and ')}, which have no common type"
        end

        type = @tast.create_array_type(types.reduce { |left, right| TypeUnion.of(@tast, left, right) }, elements.length)
        @tast.create_array(elements, type, span_of(node))
      end

      # The capacity must be settled while compiling. The initial value may be left out, in
      # which case the storage is not written and the element type comes from the first
      # assignment instead.
      def infer_array_new_call(arguments, type_environment:, span:)
        capacity = constant_capacity(arguments[0], type_environment:)
        raise "Array.new: the capacity must be known at compile time" if capacity.nil?
        return @tast.create_array_fill(nil, @tast.create_array_type(nil, capacity), span) if arguments.length < 2

        value = infer_node(arguments[1], type_environment:)
        @tast.create_array_fill(value, @tast.create_array_type(@tast.value_type(value), capacity), span)
      end

      def constant_capacity(node, type_environment:)
        return nil if node.nil?
        return @constant_locals[@bareruby_ast.children_of(node)[1]] if reference_to_local?(node)

        @tast.constant_integer(infer_node(node, type_environment:))
      end

      def reference_to_local?(node)
        @bareruby_ast.node_type(node) == :reference &&
          @bareruby_ast.children_of(node)[0] == :local
      end

      # As with the empty array literal: an empty string inside a region is the one a
      # program means to grow. A literal with contents stays what it is, in Flash.
      def infer_string(node, type_environment:)
        text = @bareruby_ast.children_of(node)[0]
        return @tast.create_string(text, :String, span_of(node)) unless text.empty? && @arena

        infer_arena_string_call(nil, type_environment:, span: span_of(node))
      end

      # A missing else is the Nil branch. Branch-local environments preserve the
      # truthiness fact while each arm is inferred, then merge back into a T? where one
      # path has Nil or never assigned a new local.
      def infer_if(node, type_environment:)
        condition, then_body, else_body = @bareruby_ast.children_of(node)
        condition_tast = infer_node(condition, type_environment:)
        then_type_environment = type_environment.branched
        else_type_environment = type_environment.branched
        then_type_environment.narrow(condition_tast, truthy: true)
        else_type_environment.narrow(condition_tast, truthy: false)

        then_tast = infer_body(then_body, type_environment: then_type_environment)
        else_tast = else_body && infer_body(else_body, type_environment: else_type_environment)
        then_type = branch_type(then_tast)
        else_type = else_tast ? branch_type(else_tast) : :Nil
        type_environment.merge_branch(
          then_type_environment, else_type_environment,
          left_reachable: then_type != :NoReturn, right_reachable: else_type != :NoReturn
        )
        type = TypeUnion.of(@tast, then_type, else_type)
        @tast.create_if(condition_tast, then_tast, else_tast, type, span_of(node))
      end

      def branch_type(statements)
        return :Nil if statements.empty?
        return :NoReturn if terminator?(statements.last)

        @tast.value_type(statements.last)
      end

      def terminator?(node) = %i[return iteration_control].include?(@tast.node_type(node))

      def infer_while(node, type_environment:)
        condition, body = @bareruby_ast.children_of(node)
        condition_tast = infer_node(condition, type_environment:)
        body_type_environment = type_environment.branched
        body_type_environment.narrow(condition_tast, truthy: true)
        typed_body = infer_body(body, type_environment: body_type_environment)
        type_environment.narrow(condition_tast, truthy: false)
        type_environment.merge_loop(body_type_environment)
        @tast.create_while(condition_tast, typed_body, span_of(node))
      end

      def infer_logical(node, type_environment:)
        operator, left, right = @bareruby_ast.children_of(node)
        left_tast = infer_node(left, type_environment:)
        right_type_environment = type_environment.branched
        right_type_environment.narrow(left_tast, truthy: operator == :and)
        right_tast = infer_node(right, type_environment: right_type_environment)
        left_type = @tast.value_type(left_tast)
        right_type = @tast.value_type(right_tast)
        type =
          if operator == :or && TypeUnion.nilable?(left_type)
            TypeUnion.of(@tast, left_type[:inner], right_type)
          elsif operator == :or && left_type == :Nil
            right_type
          elsif operator == :and && TypeUnion.nilable?(left_type)
            TypeUnion.of(@tast, :Nil, right_type)
          else
            TypeUnion.of(@tast, left_type, right_type)
          end
        @tast.create_logical(operator, left_tast, right_tast, type, span_of(node))
      end

      def infer_constant_path(node)
        owner, name = @bareruby_ast.children_of(node)
        value = Peripheral[owner].constant(name)
        @tast.create_integer(value, TypeUnion.literal(value), span_of(node))
      end

      def infer_reference(node, type_environment:)
        kind, name = @bareruby_ast.children_of(node)
        case kind
        when :local
          binding, type = type_environment.fetch(name)
          # **A name that can only ever be nil is nil.** It has no storage to read, so
          # reading it produces the one value it stands for, settled while compiling.
          return @tast.create_nil(span_of(node)) if type == :Nil

          @tast.create_reference(binding, type, span_of(node))
        when :instance
          type = @classes.fetch(type_environment.self_class).ivar_type(name)
          binding = @tast.create_binding(:instance, name, type)
          @tast.create_reference(binding, type, span_of(node))
        end
      end

      def infer_assignment(node, type_environment:)
        target, value = @bareruby_ast.children_of(node)
        value_tast =
          if @bareruby_ast.node_type(value) == :interpolation
            infer_format(value, type_environment:)
          else
            infer_node(value, type_environment:)
          end
        value_type = @tast.value_type(value_tast)
        kind, name = @bareruby_ast.children_of(target)
        reject_arena_escape(kind, name, value_tast)

        binding = @tast.create_binding(kind, name)
        case kind
        when :local
          binding = @local_bindings[name] ||= binding
          binding[:type] = binding[:type] ? TypeUnion.of(@tast, binding[:type], value_type) : value_type
          type_environment.bind(name, binding, value_type)
        when :instance
          class_definition = @classes.fetch(type_environment.self_class)
          storage_type = class_definition.ivar?(name) ? TypeUnion.of(@tast, class_definition.ivar_type(name), value_type) : value_type
          unless @initializing || class_definition.initialized?(name)
            storage_type = TypeUnion.of(@tast, :Nil, storage_type)
          end
          class_definition.remember_ivar(name, storage_type)
          binding = @tast.create_binding(:instance, name, storage_type)
        end

        @tast.create_assignment(binding, value_tast, value_type, span_of(node))
      end

      def infer_return(node, type_environment:)
        value = @bareruby_ast.children_of(node)[0]
        value_tast = value && infer_node(value, type_environment:)
        @tast.create_return(value_tast, value_tast ? @tast.value_type(value_tast) : :Nil, span_of(node))
      end

      def infer_iteration_control(node)
        @tast.create_iteration_control(@bareruby_ast.children_of(node)[0], span_of(node))
      end

      def infer_call(node, type_environment:)
        receiver, name, arguments, block = @bareruby_ast.children_of(node)
        span = span_of(node)

        if receiver.nil?
          case name
          when :puts then infer_puts_call(arguments, type_environment:, span:)
          when :loop then infer_loop_call(block, type_environment:, span:)
          when :raise then infer_raise_call(arguments, type_environment:, span:)
          when :arena then infer_arena_call(arguments, block, type_environment:, span:)
          else
            if BindingFunction.bare?(name)
              infer_binding_function_call(name, arguments, type_environment:, span:)
            else
              infer_self_method_call(name, arguments, type_environment:, span:)
            end
          end
        elsif constant_receiver?(receiver) && BindingFunction.module?(@bareruby_ast.children_of(receiver)[1])
          infer_module_function_call(
            @bareruby_ast.children_of(receiver)[1], name, arguments, type_environment:, span:
          )
        elsif constant_path_receiver?(receiver) && name == :new
          infer_constant_path_new_call(receiver, arguments, type_environment:, span:)
        elsif constant_receiver?(receiver) && name == :new
          class_name = @bareruby_ast.children_of(receiver)[1]
          if class_name == :Array
            infer_array_new_call(arguments, type_environment:, span:)
          elsif Peripheral.known?(class_name)
            infer_binding_new_call(class_name, arguments, type_environment:, span:)
          else
            infer_new_call(class_name, arguments, type_environment:, span:)
          end
        else
          receiver_tast = infer_node(receiver, type_environment:)
          receiver_type = @tast.value_type(receiver_tast)

          if name == :nil?
            infer_nil_predicate(receiver_tast, receiver_type, span)
          elsif array_type?(receiver_type)
            infer_array_method_call(name, receiver_tast, receiver_type, arguments, type_environment:, span:)
          elsif ArenaArray.type?(receiver_type)
            infer_arena_array_method_call(name, receiver_tast, receiver_type, arguments, type_environment:, span:)
          elsif ArenaString.type?(receiver_type)
            infer_arena_string_method_call(name, receiver_tast, arguments, type_environment:, span:)
          elsif StringView.type?(receiver_type)
            infer_string_view_method_call(name, receiver_tast, arguments, type_environment:, span:)
          elsif Fixed.conversion?(name)
            infer_conversion_call(name, receiver_tast, receiver_type, span)
          elsif operator?(name)
            infer_operator_call(name, receiver_tast, receiver_type, arguments, type_environment:, span:)
          elsif RECEIVER_ITERATOR_NAMES.include?(name)
            infer_iterator_call(name, receiver_tast, receiver_type, arguments, block, type_environment:, span:)
          elsif realtime_handler?(receiver_type, name)
            infer_realtime_handler_call(receiver_type, receiver_tast, name, arguments, block,
                                        type_environment:, span:)
          else
            infer_instance_method_call(receiver_tast, receiver_type, name, arguments, type_environment:, span:)
          end
        end
      end

      def infer_nil_predicate(receiver_tast, receiver_type, span)
        return @tast.create_boolean(true, :Bool, span) if receiver_type == :Nil
        return @tast.create_boolean(false, :Bool, span) unless TypeUnion.nilable?(receiver_type)

        callee = @tast.create_callee(:builtin_nil_p, nil, :nil?, nil, [], :Bool)
        @tast.create_call(receiver_tast, callee, [], nil, :Bool, span)
      end

      def array_type?(type) = type.is_a?(Hash) && type[:kind] == :array

      # size folds to the capacity because a fixed-capacity array can have no other length
      # Indexing is pointer arithmetic and is not range checked, at compile time or at run
      # time; a negative index is out of range like any other and is left alone.
      def infer_array_method_call(name, receiver_tast, receiver_type, arguments, type_environment:, span:)
        return @tast.create_array_dup(receiver_tast, receiver_type, span) if name == :dup

        capacity = receiver_type[:capacity]
        return @tast.create_integer(capacity, TypeUnion.literal(capacity), span) if SIZE_NAMES.include?(name)

        raise "a fixed-capacity array answers [], []=, size, length and dup, not #{name}" unless INDEX_NAMES.include?(name)

        index = infer_node(arguments[0], type_environment:)
        return infer_index_assign(receiver_tast, receiver_type, index, arguments[1], type_environment:, span:) if name == :[]=

        element_type = receiver_type[:element]
        raise "the element type of this array is not known yet" if element_type.nil?

        @tast.create_index(receiver_tast, index, element_type, span)
      end

      # Array.new(n) leaves the element type open, and the first assignment settles it
      # The type hash is shared with every reference to the array, so filling it in here
      # reaches all of them.
      def infer_index_assign(receiver_tast, receiver_type, index, value_node, type_environment:, span:)
        value = infer_node(value_node, type_environment:)
        receiver_type[:element] ||= @tast.value_type(value)
        @tast.create_index_assign(receiver_tast, index, value, receiver_type[:element], span)
      end

      # `arena(N)` asks for N bytes here. Which role the block plays is not settled while
      # compiling — a block written in a method is outermost or nested depending on who
      # calls that method — so the size is carried through and the guard decides on the way
      # in. Written without a size the block asks for nothing and is a release point only.
      def infer_arena_call(arguments, block, type_environment:, span:)
        size = arguments.empty? ? 0 : constant_capacity(arguments[0], type_environment:)
        raise "arena: the size must be known at compile time" if size.nil?

        _parameters, body = @bareruby_ast.children_of(block)
        # A name the block introduces does not exist after it, as in Ruby, so the body gets
        # an environment of its own. Without that the next block would see it as a name
        # that outlives a region and refuse what the region hands out.
        block_type_environment = type_environment.branched

        typed_body = inside_arena(Arena.new(enclosing: @arena, outer_names: type_environment.names)) do
          infer_body(body, type_environment: block_type_environment)
        end

        @tast.create_arena(size, typed_body, span)
      end

      # The length is a run-time value: reserving room for it is the whole reason the
      # arena exists. The element type is left open and the first assignment settles it,
      # as Array.new(n) does, and the elements start at the default of whatever that turns
      # out to be.
      def infer_arena_array_new_call(arguments, type_environment:, span:)
        length = arguments.empty? ? @tast.create_integer(0, TypeUnion.literal(0), span) :
                 infer_node(arguments[0], type_environment:)
        initial = arguments.length < 2 ? nil : infer_node(arguments[1], type_environment:)
        element = initial && @tast.value_type(initial)
        @tast.create_arena_alloc(length, initial, ArenaArray.type(@tast, element), span)
      end

      # The string a program can grow. Its handle lives in the region along with its bytes,
      # so every binding names the one string — appending through any of them is seen
      # through all of them, which is what Ruby does — and a method can hand one back.
      # The initial contents may be a static string, another variable-length string, or an
      # interpolation, which is the one form whose length is measured while running rather
      # than estimated while compiling.
      def infer_arena_string_call(source, type_environment:, span:)
        if formatted?(source)
          arguments = format_arguments(current_arena(span), source, type_environment:, span:)
          return string_call(:string, ArenaString::FORMAT_FUNCTION, arguments, ArenaString.type(@tast), span)
        end

        initial = source ? text_of(source, type_environment:) : @tast.create_string("", :String, span)
        string_call(
          :string, ArenaString::NEW_FUNCTION, [current_arena(span), initial], ArenaString.type(@tast), span
        )
      end

      # Growing, joining and comparing all reach the runtime, which owns the representation:
      # nothing the backend emits knows what a string is made of.
      def infer_arena_string_method_call(name, receiver_tast, arguments, type_environment:, span:)
        return receiver_tast if name == :to_s
        return string_call(name, ArenaString::LENGTH_FUNCTION, [receiver_tast], :Int32, span) if SIZE_NAMES.include?(name)
        return string_call(name, ArenaString::DUP_FUNCTION, [receiver_tast], ArenaString.type(@tast), span) if name == :dup

        source = arguments.first
        if name == :<< && formatted?(source)
          appended = format_arguments(receiver_tast, source, type_environment:, span:)
          return string_call(name, ArenaString::APPEND_FORMAT_FUNCTION, appended, ArenaString.type(@tast), span)
        end

        infer_string_operator_call(name, receiver_tast, source, type_environment:, span:)
      end

      def infer_string_operator_call(name, receiver_tast, source, type_environment:, span:)
        function = ArenaString.operator_function(name)
        comparison = COMPARISON_OPERATORS.include?(name)
        arguments = [receiver_tast, text_of(source, type_environment:)]
        call = string_call(name, function, arguments, comparison ? :Bool : ArenaString.type(@tast), span)
        name == :!= ? negate(call, span) : call
      end

      # A view compares against a static string through a helper the header carries,
      # deliberately outside the string runtime: the bytes are a binding's, not a region's.
      def infer_string_view_method_call(name, receiver_tast, arguments, type_environment:, span:)
        raise "a string view answers == and !=, not #{name}" unless %i[== !=].include?(name)

        call = string_call(name, StringView::EQUAL_FUNCTION,
                           [receiver_tast, text_of(arguments.first, type_environment:)], :Bool, span)
        name == :!= ? negate(call, span) : call
      end

      def format_arguments(receiver_tast, source, type_environment:, span:)
        format = format_of(source, type_environment:)
        [receiver_tast, @tast.create_string(format.text, :String, span)] + format.values
      end

      def negate(node, span)
        callee = @tast.create_callee(:builtin_operator, nil, :!, nil, [], :Bool)
        @tast.create_call(node, callee, [], nil, :Bool, span)
      end

      def string_call(name, function, arguments, return_type, span)
        callee = @tast.create_callee(
          :builtin_function, nil, name, function, argument_types(arguments), return_type
        )
        @tast.create_call(nil, callee, arguments, nil, return_type, span)
      end

      def text_of(node, type_environment:) = ArenaString.bytes_of(@tast, infer_node(node, type_environment:))

      # size is a field rather than a folded constant, because an arena array is the one
      # array whose length the compiler does not know. Writing past the end grows it, so
      # the write goes through the runtime while the read stays pointer arithmetic.
      def infer_arena_array_method_call(name, receiver_tast, receiver_type, arguments, type_environment:, span:)
        return @tast.create_arena_length(receiver_tast, :Int32, span) if SIZE_NAMES.include?(name)
        return @tast.create_arena_dup(receiver_tast, receiver_type, span) if name == :dup
        return infer_arena_push(receiver_tast, receiver_type, arguments[0], type_environment:, span:) if name == :<<

        raise "a growing array answers [], []=, <<, size, length and dup, not #{name}" unless INDEX_NAMES.include?(name)

        index = infer_node(arguments[0], type_environment:)
        if name == :[]=
          value = infer_node(arguments[1], type_environment:)
          receiver_type[:element] ||= @tast.value_type(value)
          return @tast.create_arena_index_assign(receiver_tast, index, value, receiver_type[:element], span)
        end

        element_type = receiver_type[:element]
        raise "the element type of this arena array is not known yet" if element_type.nil?

        @tast.create_index(receiver_tast, index, element_type, span)
      end

      # Appending is writing at the length the array has right now, which the runtime reads
      # for itself: the index the caller would have to compute is the one it already knows.
      def infer_arena_push(receiver_tast, receiver_type, value_node, type_environment:, span:)
        value = infer_node(value_node, type_environment:)
        receiver_type[:element] ||= @tast.value_type(value)
        @tast.create_arena_push(receiver_tast, value, receiver_type, span)
      end

      # The simple check the design asks for while a full lifetime analysis is still out
      # of scope: what a region hands out may not be stored where the release cannot reach
      # it. An instance variable outlives every block, and so does a local the block did
      # not introduce. Returning one is not an escape — the caller's region is still there.
      # With `arena` a form rather than a value there is no region to store, only what it
      # handed out, so the check has one case instead of three.
      def reject_arena_escape(kind, name, value_tast)
        type = @tast.value_type(value_tast)
        return unless ArenaArray.type?(type) || ArenaString.type?(type)
        return unless kind == :instance || @arena&.outlived_by?(name)

        raise "what an arena holds cannot be stored in #{name}, which outlives it"
      end

      def constant_receiver?(receiver)
        @bareruby_ast.node_type(receiver) == :reference &&
          @bareruby_ast.children_of(receiver)[0] == :constant
      end

      def constant_path_receiver?(receiver) = @bareruby_ast.node_type(receiver) == :constant_path

      # `Arena::Array` and `Arena::String` are the two the first two layers cannot hold, and
      # a leading `::` is how a program reaches the fixed-capacity array from inside a
      # region, where a bare literal would mean the growing one.
      def infer_constant_path_new_call(receiver, arguments, type_environment:, span:)
        owner, name = @bareruby_ast.children_of(receiver)
        if Arena.member?(owner, name)
          return infer_arena_array_new_call(arguments, type_environment:, span:) if name == Arena::ARRAY_NAME

          return infer_arena_string_call(arguments.first, type_environment:, span:)
        end
        raise "#{owner}::#{name}.new is not a form this compiler knows" unless owner.nil? && name == :Array

        infer_array_new_call(arguments, type_environment:, span:)
      end

      def infer_self_method_call(name, arguments, type_environment:, span:)
        if binding_method?(type_environment.self_class, name)
          return infer_binding_method_call(
            nil, type_environment.self_class, name, arguments, type_environment:, span:
          )
        end

        argument_tasts = arguments.map { |argument| infer_node(argument, type_environment:) }
        resolved = resolve_method_call(method_named(type_environment.self_class, name), argument_types(argument_tasts))
        callee = @tast.create_callee(
          :user_method, resolved.owner, name, function_name(resolved.owner, name),
          resolved.parameter_types, resolved.return_type
        )
        @tast.create_call(nil, callee, argument_tasts, nil, resolved.return_type, span)
      end

      # **A peripheral answers a name the mapping does not have the way any class does.**
      # The C functions are the hardware's vocabulary; what a program says to the class
      # above them is the class's own Ruby, and there is one rule for finding a method in
      # Ruby. So the mapping is asked first and the class after — asked in the other order,
      # a peripheral would be answering for names it never declared.
      def binding_method?(class_name, name)
        !class_name.nil? && Peripheral.known?(class_name) && Peripheral[class_name].mapped?(name)
      end

      def infer_instance_method_call(receiver_tast, receiver_type, name, arguments, type_environment:, span:)
        class_name = receiver_type[:class_name]
        if binding_method?(class_name, name)
          signature = Peripheral[class_name].method_signature(name)
          printf_function = signature[:printf_function]
          if printf_function && formatted?(arguments.first)
            return infer_printf_call(
              printf_function, receiver_tast, arguments.first, type_environment:, span:
            )
          end

          return infer_binding_method_call(
            receiver_tast, class_name, name, arguments, type_environment:, span:
          )
        end

        argument_tasts = arguments.map { |argument| infer_node(argument, type_environment:) }

        resolved = resolve_method_call(method_named(class_name, name), argument_types(argument_tasts))
        callee = @tast.create_callee(
          :user_method, resolved.owner, name, function_name(resolved.owner, name),
          resolved.parameter_types, resolved.return_type
        )
        @tast.create_call(receiver_tast, callee, argument_tasts, nil, resolved.return_type, span)
      end

      # Whichever region is current. A binding that needs somewhere to put what it receives
      # asks for this rather than for a name the program wrote, because the program writes
      # none.
      def current_arena(span) = @tast.create_arena_current(span)

      def inside_arena(arena)
        enclosing = @arena
        @arena = arena
        yield
      ensure
        @arena = enclosing
      end

      def infer_new_call(class_name, arguments, type_environment:, span:)
        argument_tasts = arguments.map { |argument| infer_node(argument, type_environment:) }
        types = argument_types(argument_tasts)
        resolve_method_call(method_named(class_name, :initialize), types)
        instance_type = @tast.create_instance_type(class_name)
        callee = @tast.create_callee(
          :new, class_name, :new, function_name(class_name, :initialize), types, instance_type
        )
        @tast.create_call(nil, callee, argument_tasts, nil, instance_type, span)
      end

      def infer_binding_new_call(class_name, arguments, type_environment:, span:)
        peripheral = Peripheral[class_name]
        argument_tasts = resolve_keywords(
          arguments, peripheral.constructor_keywords, "#{class_name}.new", type_environment:, span:
        )
        instance_type = peripheral.instance_type(@tast)
        callee = @tast.create_callee(
          :binding_new, class_name, :new, peripheral.constructor_function,
          argument_types(argument_tasts), instance_type
        )
        @tast.create_call(nil, callee, argument_tasts, nil, instance_type, span)
      end

      # A fixed key set: every declared keyword becomes a
      # trailing positional parameter, in declaration order, defaulted when absent.
      #
      # **A keyword the declaration does not have is refused rather than dropped.** A
      # peripheral that quietly ignores what it was told looks exactly like one that
      # obeyed: the program says 7E1 and the wire carries 8N1, and nothing anywhere says
      # so. Which keywords a peripheral takes is its declaration's answer, so a key that
      # is not in it is a question this side can settle and must.
      def resolve_keywords(arguments, keywords, subject, type_environment:, span:)
        positional, keyword_nodes = arguments.partition do |argument|
          @bareruby_ast.node_type(argument) != :keyword_argument
        end
        supplied = keyword_nodes.to_h do |argument|
          name, value = @bareruby_ast.children_of(argument)
          [name, value]
        end
        refuse_unknown_keywords(supplied.keys, keywords, subject)

        tasts = positional.map { |argument| infer_node(argument, type_environment:) }
        keywords.each do |name, default|
          value = supplied[name]
          tasts << (value ? infer_node(value, type_environment:) : default_written(default, span))
        end
        tasts
      end

      # What a keyword left out stands for. A default is written in the declaration in the
      # type the call takes, so the literal the program did not write is built in that type.
      def default_written(default, span)
        return @tast.create_boolean(default, :Bool, span) if [true, false].include?(default)

        @tast.create_integer(default, TypeUnion.literal(default), span)
      end

      def refuse_unknown_keywords(supplied, keywords, subject)
        unknown = supplied - keywords.keys
        return if unknown.empty?

        raise "#{subject} takes #{spelled(keywords.keys)}, not #{spelled(unknown)}"
      end

      def keyword_names(arguments)
        arguments.filter_map do |argument|
          @bareruby_ast.children_of(argument)[0] if @bareruby_ast.node_type(argument) == :keyword_argument
        end
      end

      def spelled(names)
        return "no keywords" if names.empty?

        names.map { |name| "#{name}:" }.join(", ")
      end

      # **What a peripheral call takes beyond what the program wrote is the declaration's
      # answer, not a class this side recognises.** Two of them are stated there. A call
      # that answers a variable-length string needs somewhere to put it, and the declared
      # return type already says which calls those are. A call that gathers its trailing
      # arguments into one byte sequence needs somewhere to build it, and the declaration
      # says where those arguments begin. Either way the region is an implementation
      # argument: the Ruby call keeps the shape the program wrote.
      def infer_binding_method_call(receiver_tast, class_name, name, arguments, type_environment:, span:)
        signature = Peripheral[class_name].method_signature(name)
        refuse_unknown_keywords(keyword_names(arguments), signature[:keywords] || {}, "#{class_name}##{name}")
        argument_tasts = written_arguments(arguments, signature[:payload_from], type_environment:)
        argument_tasts = [current_arena(span)] + argument_tasts if region_of(signature)
        return_type = answers_string?(signature) ? ArenaString.type(@tast) : signature[:return_type]
        callee = @tast.create_callee(
          signature[:payload_from] ? :binding_payload : :binding_method,
          class_name, name, signature[:function], argument_types(argument_tasts), return_type
        )
        @tast.create_call(receiver_tast, callee, argument_tasts, nil, return_type, span)
      end

      # What a variable-length string among the arguments is passed as. The ones gathered
      # into a byte sequence are left whole, because gathering them is what the pass that
      # builds the sequence does with them.
      def written_arguments(arguments, payload_from, type_environment:)
        arguments.each_with_index.map do |argument, index|
          argument_tast = infer_node(argument, type_environment:)
          payload_from && index >= payload_from ? argument_tast : ArenaString.bytes_of(@tast, argument_tast)
        end
      end

      def answers_string?(signature) = signature[:return_type] == :arena_string

      def region_of(signature) = answers_string?(signature) || !signature[:payload_from].nil?

      # A peripheral method whose declaration says its block becomes a realtime handler.
      # **Which methods those are is the peripheral's answer, not a name known here** — the
      # handler itself, the context it runs in and the checks it is subject to are the
      # language's, and they are the same whatever hardware asked for one.
      def realtime_handler?(receiver_type, name)
        return false unless receiver_type.is_a?(Hash) && receiver_type[:class_name]
        return false unless Peripheral.known?(receiver_type[:class_name])

        Peripheral[receiver_type[:class_name]].block_of(name) == :realtime_handler
      end

      # The registration arguments and the handler's parameters are both the declaration's
      # answer: keywords become trailing positionals as everywhere else, and a declared
      # block parameter type names what the binding will hand the handler. The handler
      # still sees no outer names — its parameters are the only ones it starts with.
      def infer_realtime_handler_call(receiver_type, receiver_tast, name, arguments, block,
                                      type_environment:, span:)
        signature = Peripheral[receiver_type[:class_name]].method_signature(name)
        registration = resolve_keywords(
          arguments, signature[:keywords] || {}, "#{receiver_type[:class_name]}##{name}", type_environment:, span:
        )
        parameters, body = @bareruby_ast.children_of(block)
        parameter_types = (signature[:block_parameter_types] || [])
                          .map { |declared| StringView.block_parameter_type(@tast, declared) }
        handler_environment = type_environment.without_locals
        typed_parameters = block_parameters(parameters, parameter_types, handler_environment, span_of(block))
        typed_body = infer_body(body, type_environment: handler_environment)
        typed_block = @tast.create_block(typed_parameters, typed_body, :Nil, span_of(block))
        @tast.create_interrupt(receiver_tast, registration, typed_block, signature[:function], :Nil, span)
      end

      def infer_module_function_call(module_name, name, arguments, type_environment:, span:)
        signature = BindingFunction.of_module(module_name, name)
        infer_binding_signature_call(signature, module_name, name, "#{module_name}.#{name}",
                                     arguments, type_environment:, span:)
      end

      def infer_binding_function_call(name, arguments, type_environment:, span:)
        infer_binding_signature_call(BindingFunction.bare(name), nil, name, name.to_s,
                                     arguments, type_environment:, span:)
      end

      # **A function reached without a receiver takes its keywords the way a peripheral
      # does** — declared, defaulted, and turned into trailing positionals in declaration
      # order. There is one rule for what a keyword is in this language, and the waits are
      # not an exception to it just because no object owns them.
      def infer_binding_signature_call(signature, owner, name, subject, arguments, type_environment:, span:)
        argument_tasts = resolve_keywords(
          arguments, signature[:keywords] || {}, subject, type_environment:, span:
        )
        callee = @tast.create_callee(
          :binding_function, owner, name, signature[:function],
          signature[:parameter_types], signature[:return_type]
        )
        @tast.create_call(nil, callee, argument_tasts, nil, signature[:return_type], span)
      end

      # ? and ! are legal in Ruby method names but not in C identifiers.
      def function_name(owner, name)
        :"#{owner}_#{name.to_s.sub(/\?\z/, '_p').sub(/!\z/, '_bang').sub(/=\z/, '_set')}"
      end

      # A conversion whose source already has the target type is the identity.
      def infer_conversion_call(name, receiver_tast, receiver_type, span)
        conversion = Fixed.conversion(name)
        return receiver_tast if receiver_type == conversion[:return_type]
        return Fixed.of(@tast, receiver_tast) if name == :to_fixed

        callee = @tast.create_callee(
          :builtin_function, nil, name, conversion[:function], [receiver_type], conversion[:return_type]
        )
        @tast.create_call(nil, callee, [receiver_tast], nil, conversion[:return_type], span)
      end

      # An integer operand joins the fraction rather than the other way round, so both
      # sides are scaled before the operation is chosen.
      def infer_fixed_operator_call(name, receiver_tast, argument_tasts, span)
        receiver = Fixed.of(@tast, receiver_tast)
        arguments = argument_tasts.map { |argument| Fixed.of(@tast, argument) }

        return Fixed.runtime_call(@tast, name, receiver, arguments, span) if Fixed.runtime_operator?(name)

        result_type = COMPARISON_OPERATORS.include?(name) ? :Bool : :Fixed
        callee = @tast.create_callee(:builtin_operator, nil, name, nil, argument_types(arguments), result_type)
        @tast.create_call(receiver, callee, arguments, nil, result_type, span)
      end

      def operator?(name)
        UNARY_OPERATORS.include?(name) || BINARY_OPERATORS.include?(name) ||
          COMPARISON_OPERATORS.include?(name) || name == :!
      end

      def infer_operator_call(name, receiver_tast, receiver_type, arguments, type_environment:, span:)
        argument_tasts = arguments.map { |argument| infer_node(argument, type_environment:) }
        if Fixed.type?(receiver_type) || argument_tasts.any? { |a| Fixed.type?(@tast.value_type(a)) }
          return infer_fixed_operator_call(name, receiver_tast, argument_tasts, span)
        end

        result_type =
          if COMPARISON_OPERATORS.include?(name) || name == :!
            :Bool
          elsif UNARY_OPERATORS.include?(name)
            receiver_type
          else
            TypeUnion.widest(receiver_type, @tast.value_type(argument_tasts.first))
          end
        callee = @tast.create_callee(:builtin_operator, nil, name, nil, argument_types(argument_tasts), result_type)
        @tast.create_call(receiver_tast, callee, argument_tasts, nil, result_type, span)
      end

      def infer_iterator_call(name, receiver_tast, receiver_type, arguments, block, type_environment:, span:)
        argument_tasts = arguments.map { |argument| infer_node(argument, type_environment:) }
        element_type = name == :upto ? TypeUnion.widest(receiver_type, @tast.value_type(argument_tasts.first)) : receiver_type
        block_tast = block && infer_iterator_block(block, [element_type], type_environment:)
        callee = @tast.create_callee(:builtin_iterator, nil, name, nil, argument_types(argument_tasts), :Nil)
        @tast.create_call(receiver_tast, callee, argument_tasts, block_tast, :Nil, span)
      end

      def infer_loop_call(block, type_environment:, span:)
        block_tast = block && infer_iterator_block(block, [], type_environment:)
        callee = @tast.create_callee(:builtin_iterator, nil, :loop, nil, [], :Nil)
        @tast.create_call(nil, callee, [], block_tast, :Nil, span)
      end

      # puts is expanded at compile time: an interpolation becomes a format string plus
      # its values, with no intermediate buffer.
      def infer_puts_call(arguments, type_environment:, span:)
        argument = arguments.first
        return infer_printf_call(:bareruby_printf, nil, argument, type_environment:, span:) if formatted?(argument)

        argument_tasts = arguments.map { |a| text_of(a, type_environment:) }
        callee = @tast.create_callee(
          :builtin_puts, nil, :puts, puts_function(argument_tasts), argument_types(argument_tasts), :Nil
        )
        @tast.create_call(nil, callee, argument_tasts, nil, :Nil, span)
      end

      def formatted?(node) = !node.nil? && @bareruby_ast.interpolation?(node)

      def infer_printf_call(function, receiver_tast, node, type_environment:, span:)
        format = format_of(node, type_environment:)
        arguments = [@tast.create_string("#{format.text}\n", :String, span_of(node))] + format.values
        kind = receiver_tast ? :binding_printf : :builtin_printf
        callee = @tast.create_callee(kind, nil, :printf, function, argument_types(arguments), :Nil)
        @tast.create_call(receiver_tast, callee, arguments, nil, :Nil, span)
      end

      # An interpolation outside a puts argument becomes a fixed-capacity buffer plus a
      # compile-time bound on what can land in it. An arena string is the way out of that
      # estimate: a.string("...") measures the rendering while running instead.
      def infer_format(node, type_environment:)
        format = format_of(node, type_environment:)
        @tast.create_format(
          format.capacity, @tast.create_string(format.text, :String, span_of(node)),
          format.values, :String, span_of(node)
        )
      end

      def format_of(node, type_environment:)
        parts = @bareruby_ast.children_of(node)[0].map { |part| infer_node(part, type_environment:) }
        PrintfFormat.new(parts, @tast)
      end

      def infer_iterator_block(block_node, value_types, type_environment:)
        parameters, body = @bareruby_ast.children_of(block_node)
        block_type_environment = type_environment.branched
        typed_parameters = block_parameters(parameters, value_types, block_type_environment, span_of(block_node))
        typed_body = infer_body(body, type_environment: block_type_environment)
        @tast.create_block(typed_parameters, typed_body, :Nil, span_of(block_node))
      end

      # **A block takes what it is handed, and the two do not have to be the same length.**
      # A value nobody named is dropped and a name nothing was handed to is nil, which is
      # what Ruby does on both sides. What is emitted is one parameter per value, because
      # the shape of the thing that runs the block is the sender's — a handler is called
      # through a pointer whose type the binding wrote, and a counted loop needs its
      # counter whether or not the block asked for it. A name beyond them is bound and not
      # emitted: it stands for nil, and nil is not something this language stores.
      def block_parameters(parameters, value_types, environment, span)
        names = parameters.map { |parameter| @bareruby_ast.children_of(parameter)[0] }
        taken = value_types.each_with_index.map do |type, index|
          binding = @tast.create_binding(:local, names[index] || :"bareruby_unnamed_#{index}")
          environment.bind(binding[:name], binding, type) if names[index]
          @tast.create_parameter(binding, type, span)
        end
        names.drop(value_types.length).each do |name|
          environment.bind(name, @tast.create_binding(:local, name), :Nil)
        end
        taken
      end

      def argument_types(argument_tasts) = argument_tasts.map { |argument| @tast.value_type(argument) }

      def puts_function(argument_tasts)
        case @tast.value_type(argument_tasts.first)
        when :Int64 then :bareruby_puts_int64
        when :String then :bareruby_puts_string
        when :Bool then :bareruby_puts_bool
        when :Fixed then :bareruby_puts_fixed
        else :bareruby_puts_int32
        end
      end

      def span_of(node) = @bareruby_ast.span_of(node)
    end
  end
end
