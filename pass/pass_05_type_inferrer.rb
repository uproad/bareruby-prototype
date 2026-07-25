# frozen_string_literal: true

require_relative "../ir/tir"

module BareRubyProt
  module Pass
    class TypeInferrer
      RECEIVER_ITERATOR_NAMES = %i[times upto].freeze
      UNARY_OPERATORS = %i[-@ ~].freeze
      BINARY_OPERATORS = %i[+ - * / % << >> & | ^].freeze
      COMPARISON_OPERATORS = %i[== != < <= > >=].freeze
      FIXED_ONE = 65_536
      CONVERSIONS = {
        to_fixed: { function: :bareruby_int32_to_fixed, return_type: :Fixed, from: :Int32 },
        to_i32: { function: :bareruby_fixed_to_i32, return_type: :Int32, from: :Fixed }
      }.freeze
      INTEGER_WIDTHS = %i[Int8 Int16 Int32 Int64].freeze
      INTEGER_RANGES = {
        Int8: (-128..127),
        Int16: (-32_768..32_767),
        Int32: (-(2**31)..(2**31 - 1)),
        Int64: (-(2**63)..(2**63 - 1))
      }.freeze

      PERIPHERAL_CLASSES = {
        GPIO: {
          struct: :bareruby_gpio_t,
          constants: { IN: 0, OUT: 1, HIGH_Z: 2, PULL_UP: 4, PULL_DOWN: 8, OPEN_DRAIN: 16 },
          constructor: { function: :bareruby_gpio_init, parameter_types: %i[Int32 Int32] },
          methods: {
            write: { function: :bareruby_gpio_write, parameter_types: %i[Int32], return_type: :Nil },
            read: { function: :bareruby_gpio_read, parameter_types: [], return_type: :Int32 },
            high?: { function: :bareruby_gpio_high, parameter_types: [], return_type: :Bool },
            low?: { function: :bareruby_gpio_low, parameter_types: [], return_type: :Bool }
          }
        }
      }.freeze

      PERIPHERAL_CLASSES_EXTRA = {
        PWM: {
          struct: :bareruby_pwm_t,
          constants: {},
          constructor: {
            function: :bareruby_pwm_init,
            parameter_types: %i[Int32],
            keywords: { frequency: 0, duty: 0 }
          },
          methods: {
            frequency: { function: :bareruby_pwm_frequency, parameter_types: %i[Int32], return_type: :Nil },
            period_us: { function: :bareruby_pwm_period_us, parameter_types: %i[Int32], return_type: :Nil },
            duty: { function: :bareruby_pwm_duty, parameter_types: %i[Int32], return_type: :Nil },
            pulse_width_us: {
              function: :bareruby_pwm_pulse_width_us, parameter_types: %i[Int32], return_type: :Nil
            }
          }
        },
        UART: {
          struct: :bareruby_uart_t,
          constants: { NONE: 0, EVEN: 1, ODD: 2, RTSCTS: 4 },
          constructor: {
            function: :bareruby_uart_init,
            parameter_types: %i[Int32],
            keywords: { baud: 115_200, parity: 0 }
          },
          methods: {
            write: { function: :bareruby_uart_write, parameter_types: %i[String], return_type: :Int32 },
            puts: { function: :bareruby_uart_puts, parameter_types: %i[String], return_type: :Nil },
            bytes_available: {
              function: :bareruby_uart_bytes_available, parameter_types: [], return_type: :Int32
            },
            can_read_line: {
              function: :bareruby_uart_can_read_line, parameter_types: [], return_type: :Bool
            },
            flush: { function: :bareruby_uart_flush, parameter_types: [], return_type: :Nil },
            clear_rx_buffer: {
              function: :bareruby_uart_clear_rx_buffer, parameter_types: [], return_type: :Nil
            },
            clear_tx_buffer: {
              function: :bareruby_uart_clear_tx_buffer, parameter_types: [], return_type: :Nil
            }
          }
        }
      }.freeze

      PERIPHERAL_FUNCTIONS = {
        sleep: { function: :bareruby_sleep, parameter_types: %i[Int32], return_type: :Nil },
        sleep_ms: { function: :bareruby_sleep_ms, parameter_types: %i[Int32], return_type: :Nil }
      }.freeze

      PERIPHERAL_MODULES = {
        Machine: {
          delay_us: { function: :bareruby_machine_delay_us, parameter_types: %i[Int32], return_type: :Nil }
        }
      }.freeze

      # puts and write on a UART take the same printf expansion as the global puts.
      PRINTF_BINDINGS = {
        bareruby_uart_puts: :bareruby_uart_printf,
        bareruby_uart_write: :bareruby_uart_printf
      }.freeze

      PERIPHERALS = PERIPHERAL_CLASSES.merge(PERIPHERAL_CLASSES_EXTRA).freeze

      ClassInfo = Struct.new(:superclass, :methods, :ivars)
      MethodInfo = Struct.new(
        :owner, :name, :parameters, :body,
        :parameter_types, :return_type, :parameter_bindings, :typed_body
      )

      attr_reader :result

      def initialize(bareruby_ast)
        @bareruby_ast = bareruby_ast
        @tir = TIR.new
        @classes = {}
      end

      def run
        register_builtin_classes
        register_classes(@bareruby_ast.program_body)

        env = {}
        typed = @bareruby_ast.program_body.map do |statement|
          class_definition?(statement) ? statement : infer_node(statement, env:, self_class: nil)
        end

        body = @bareruby_ast.program_body.zip(typed).map do |original, typed_statement|
          class_definition?(original) ? build_class_definition(original) : typed_statement
        end

        @result = @tir.replace_program(body)

        self
      end

      def class_definition?(node) = @bareruby_ast.node_type(node) == :class_definition

      def register_builtin_classes
        @classes[:BasicObject] = ClassInfo.new(nil, {}, {})
        initialize_info = MethodInfo.new(:Object, :initialize, [], [], [], :Nil, [], [])
        @classes[:Object] = ClassInfo.new(:BasicObject, { initialize: initialize_info }, {})
      end

      def register_classes(statements)
        statements.each { |statement| register_class(statement) if class_definition?(statement) }
      end

      def register_class(node)
        name, body = @bareruby_ast.children_of(node)
        methods = body[1..].to_h do |method_node|
          method_name, parameters, method_body = @bareruby_ast.children_of(method_node)
          [method_name, MethodInfo.new(name, method_name, parameters, method_body, nil, nil, nil, nil)]
        end
        @classes[name] = ClassInfo.new(superclass_name_of(body.first), methods, {})
      end

      def superclass_name_of(include_call)
        arguments = @bareruby_ast.children_of(include_call)[2]
        @bareruby_ast.children_of(arguments.first)[1]
      end

      def find_method(class_name, name)
        current = class_name
        while current
          class_info = @classes.fetch(current)
          method_info = class_info.methods[name]
          return method_info if method_info

          current = class_info.superclass
        end
      end

      def build_class_definition(node)
        name, body = @bareruby_ast.children_of(node)
        class_info = @classes.fetch(name)
        methods = body[1..].filter_map { |method_node| build_method_definition(method_node, class_info) }
        ivars = class_info.ivars.map { |ivar_name, type| { name: ivar_name, type: } }
        @tir.create_class_definition(name, ivars, methods, span_of(node))
      end

      def build_method_definition(method_node, class_info)
        name, parameters, = @bareruby_ast.children_of(method_node)
        method_info = class_info.methods.fetch(name)
        return unless method_info.return_type

        identity = @tir.create_identity(
          method_info.owner, name, method_info.parameter_types, method_info.return_type
        )
        typed_parameters = method_info.parameter_bindings.zip(parameters, method_info.parameter_types)
                                     .map { |binding, parameter, type| @tir.create_parameter(binding, type, span_of(parameter)) }
        @tir.create_method_definition(identity, typed_parameters, method_info.typed_body, span_of(method_node))
      end

      def resolve_method_call(method_info, argument_types)
        infer_method!(method_info, argument_types) if method_info.return_type.nil?
        method_info
      end

      def infer_method!(method_info, argument_types)
        bindings = method_info.parameters.map do |parameter|
          @tir.create_binding(:local, @bareruby_ast.children_of(parameter)[0])
        end
        env = bindings.each_with_index.to_h { |binding, index| [binding[:name], [binding, argument_types[index]]] }
        typed_body = infer_body(method_info.body, env:, self_class: method_info.owner)

        method_info.parameter_types = argument_types
        method_info.parameter_bindings = bindings
        method_info.typed_body = typed_body
        method_info.return_type =
          method_info.name == :initialize ? :Nil : method_return_type(typed_body)
      end

      # Every return in the body contributes, plus the value the body falls off the end
      # with. NoReturn contributes nothing (LANGUAGE.md section 4.7).
      def method_return_type(typed_body)
        return :Nil if typed_body.empty?

        types = collect_return_types(typed_body)
        types << @tir.value_type(typed_body.last) unless terminator?(typed_body.last)
        types = types.reject { |type| type == :NoReturn }
        types.empty? ? :Nil : types.reduce { |left, right| unify(left, right) }
      end

      def collect_return_types(statements)
        statements.flat_map do |statement|
          case @tir.node_type(statement)
          when :return
            value = @tir.children_of(statement)[0]
            [@tir.value_type(statement)] + (value ? collect_return_types([value]) : [])
          when :if
            _condition, then_body, else_body, = @tir.children_of(statement)
            collect_return_types(then_body) + collect_return_types(else_body || [])
          when :while
            collect_return_types(@tir.children_of(statement)[1])
          when :call
            block = @tir.children_of(statement)[3]
            block ? collect_return_types(@tir.children_of(block)[1]) : []
          else []
          end
        end
      end

      def infer_body(statements, env:, self_class:)
        statements.map { |statement| infer_node(statement, env:, self_class:) }
      end

      def infer_node(node, env:, self_class:)
        case @bareruby_ast.node_type(node)
        when :integer then infer_integer(node)
        when :float then infer_float(node)
        when :boolean then infer_boolean(node)
        when :string then infer_string(node)
        when :symbol then infer_symbol(node)
        when :constant_path then infer_constant_path(node)
        when :if then infer_if(node, env:, self_class:)
        when :while then infer_while(node, env:, self_class:)
        when :logical then infer_logical(node, env:, self_class:)
        when :reference then infer_reference(node, env:, self_class:)
        when :assignment then infer_assignment(node, env:, self_class:)
        when :call then infer_call(node, env:, self_class:)
        when :return then infer_return(node, env:, self_class:)
        when :iteration_control then infer_iteration_control(node)
        end
      end

      def infer_integer(node)
        value = @bareruby_ast.children_of(node)[0]
        @tir.create_integer(value, literal_type(value), span_of(node))
      end

      def infer_boolean(node)
        @tir.create_boolean(@bareruby_ast.children_of(node)[0], :Bool, span_of(node))
      end

      # A decimal literal is rounded to the nearest representable Q16.16 value at compile
      # time and carried as its internal integer form (LANGUAGE.md section 5.4).
      def infer_float(node)
        value = @bareruby_ast.children_of(node)[0]
        @tir.create_integer((value * FIXED_ONE).round, :Fixed, span_of(node))
      end

      def infer_symbol(node)
        @tir.create_symbol(@bareruby_ast.children_of(node)[0], :Symbol, span_of(node))
      end

      def infer_string(node)
        @tir.create_string(@bareruby_ast.children_of(node)[0], :String, span_of(node))
      end

      # An if in value position takes the type both branches agree on; as a statement it
      # is Nil. A missing else keeps it a statement (LANGUAGE.md section 5.10). A branch
      # that always leaves contributes NoReturn, which the other branch absorbs (4.7).
      def infer_if(node, env:, self_class:)
        condition, then_body, else_body = @bareruby_ast.children_of(node)
        condition_tir = infer_node(condition, env:, self_class:)
        then_tir = infer_body(then_body, env:, self_class:)
        else_tir = else_body && infer_body(else_body, env:, self_class:)
        type = else_tir ? unify(branch_type(then_tir), branch_type(else_tir)) : :Nil
        @tir.create_if(condition_tir, then_tir, else_tir, type, span_of(node))
      end

      def branch_type(statements)
        return :Nil if statements.empty?
        return :NoReturn if terminator?(statements.last)

        @tir.value_type(statements.last)
      end

      def terminator?(node) = %i[return iteration_control].include?(@tir.node_type(node))

      def infer_while(node, env:, self_class:)
        condition, body = @bareruby_ast.children_of(node)
        condition_tir = infer_node(condition, env:, self_class:)
        @tir.create_while(condition_tir, infer_body(body, env:, self_class:), span_of(node))
      end

      def infer_logical(node, env:, self_class:)
        operator, left, right = @bareruby_ast.children_of(node)
        left_tir = infer_node(left, env:, self_class:)
        right_tir = infer_node(right, env:, self_class:)
        type = unify(@tir.value_type(left_tir), @tir.value_type(right_tir))
        @tir.create_logical(operator, left_tir, right_tir, type, span_of(node))
      end

      def infer_constant_path(node)
        owner, name = @bareruby_ast.children_of(node)
        value = PERIPHERALS.fetch(owner)[:constants].fetch(name)
        @tir.create_integer(value, literal_type(value), span_of(node))
      end

      def infer_reference(node, env:, self_class:)
        kind, name = @bareruby_ast.children_of(node)
        case kind
        when :local
          binding, type = env.fetch(name)
          @tir.create_reference(binding, type, span_of(node))
        when :instance
          type = @classes.fetch(self_class).ivars.fetch(name)
          @tir.create_reference(@tir.create_binding(:instance, name), type, span_of(node))
        end
      end

      def infer_assignment(node, env:, self_class:)
        target, value = @bareruby_ast.children_of(node)
        value_tir = infer_node(value, env:, self_class:)
        value_type = @tir.value_type(value_tir)
        kind, name = @bareruby_ast.children_of(target)

        binding = @tir.create_binding(kind, name)
        case kind
        when :local
          binding = env.key?(name) ? env.fetch(name)[0] : binding
          env[name] = [binding, value_type]
        when :instance
          ivars = @classes.fetch(self_class).ivars
          ivars[name] = value_type unless ivars.key?(name)
        end

        @tir.create_assignment(binding, value_tir, value_type, span_of(node))
      end

      def infer_return(node, env:, self_class:)
        value = @bareruby_ast.children_of(node)[0]
        value_tir = value && infer_node(value, env:, self_class:)
        @tir.create_return(value_tir, value_tir ? @tir.value_type(value_tir) : :Nil, span_of(node))
      end

      def infer_iteration_control(node)
        @tir.create_iteration_control(@bareruby_ast.children_of(node)[0], span_of(node))
      end

      def infer_call(node, env:, self_class:)
        receiver, name, arguments, block = @bareruby_ast.children_of(node)
        span = span_of(node)

        if receiver.nil?
          case name
          when :puts then infer_puts_call(arguments, env:, self_class:, span:)
          when :loop then infer_loop_call(block, env:, self_class:, span:)
          else
            if PERIPHERAL_FUNCTIONS.key?(name)
              infer_binding_function_call(name, arguments, env:, self_class:, span:)
            else
              infer_self_method_call(name, arguments, env:, self_class:, span:)
            end
          end
        elsif constant_receiver?(receiver) && PERIPHERAL_MODULES.key?(@bareruby_ast.children_of(receiver)[1])
          infer_module_function_call(
            @bareruby_ast.children_of(receiver)[1], name, arguments, env:, self_class:, span:
          )
        elsif constant_receiver?(receiver) && name == :new
          class_name = @bareruby_ast.children_of(receiver)[1]
          if PERIPHERALS.key?(class_name)
            infer_binding_new_call(class_name, arguments, env:, self_class:, span:)
          else
            infer_new_call(class_name, arguments, env:, self_class:, span:)
          end
        else
          receiver_tir = infer_node(receiver, env:, self_class:)
          receiver_type = @tir.value_type(receiver_tir)

          if CONVERSIONS.key?(name)
            infer_conversion_call(name, receiver_tir, receiver_type, span)
          elsif operator?(name)
            infer_operator_call(name, receiver_tir, receiver_type, arguments, env:, self_class:, span:)
          elsif RECEIVER_ITERATOR_NAMES.include?(name)
            infer_iterator_call(name, receiver_tir, receiver_type, arguments, block, env:, self_class:, span:)
          else
            infer_instance_method_call(receiver_tir, receiver_type, name, arguments, env:, self_class:, span:)
          end
        end
      end

      def constant_receiver?(receiver)
        @bareruby_ast.node_type(receiver) == :reference &&
          @bareruby_ast.children_of(receiver)[0] == :constant
      end

      def infer_self_method_call(name, arguments, env:, self_class:, span:)
        argument_tirs = arguments.map { |argument| infer_node(argument, env:, self_class:) }
        resolved = resolve_method_call(find_method(self_class, name), argument_types(argument_tirs))
        callee = @tir.create_callee(
          :user_method, resolved.owner, name, function_name(resolved.owner, name),
          resolved.parameter_types, resolved.return_type
        )
        @tir.create_call(nil, callee, argument_tirs, nil, resolved.return_type, span)
      end

      def infer_instance_method_call(receiver_tir, receiver_type, name, arguments, env:, self_class:, span:)
        class_name = receiver_type[:class_name]
        if PERIPHERALS.key?(class_name)
          signature = PERIPHERALS.fetch(class_name)[:methods].fetch(name)
          printf_function = PRINTF_BINDINGS[signature[:function]]
          if printf_function && formatted?(arguments.first)
            return infer_printf_call(
              printf_function, receiver_tir, arguments.first, env:, self_class:, span:
            )
          end

          argument_tirs = arguments.map { |argument| infer_node(argument, env:, self_class:) }
          return infer_binding_method_call(receiver_tir, class_name, name, argument_tirs, span)
        end

        argument_tirs = arguments.map { |argument| infer_node(argument, env:, self_class:) }

        resolved = resolve_method_call(find_method(class_name, name), argument_types(argument_tirs))
        callee = @tir.create_callee(
          :user_method, resolved.owner, name, function_name(resolved.owner, name),
          resolved.parameter_types, resolved.return_type
        )
        @tir.create_call(receiver_tir, callee, argument_tirs, nil, resolved.return_type, span)
      end

      def infer_new_call(class_name, arguments, env:, self_class:, span:)
        argument_tirs = arguments.map { |argument| infer_node(argument, env:, self_class:) }
        types = argument_types(argument_tirs)
        resolve_method_call(find_method(class_name, :initialize), types)
        instance_type = @tir.create_instance_type(class_name)
        callee = @tir.create_callee(
          :new, class_name, :new, function_name(class_name, :initialize), types, instance_type
        )
        @tir.create_call(nil, callee, argument_tirs, nil, instance_type, span)
      end

      def infer_binding_new_call(class_name, arguments, env:, self_class:, span:)
        peripheral = PERIPHERALS.fetch(class_name)
        constructor = peripheral[:constructor]
        argument_tirs = resolve_keywords(arguments, constructor[:keywords] || {}, env:, self_class:, span:)
        instance_type = @tir.create_instance_type(class_name, peripheral[:struct])
        callee = @tir.create_callee(
          :binding_new, class_name, :new, constructor[:function],
          argument_types(argument_tirs), instance_type
        )
        @tir.create_call(nil, callee, argument_tirs, nil, instance_type, span)
      end

      # A fixed key set (LANGUAGE.md section 5.7): every declared keyword becomes a
      # trailing positional parameter, in declaration order, defaulted when absent.
      def resolve_keywords(arguments, keywords, env:, self_class:, span:)
        positional, keyword_nodes = arguments.partition do |argument|
          @bareruby_ast.node_type(argument) != :keyword_argument
        end
        supplied = keyword_nodes.to_h do |argument|
          name, value = @bareruby_ast.children_of(argument)
          [name, value]
        end

        tirs = positional.map { |argument| infer_node(argument, env:, self_class:) }
        keywords.each do |name, default|
          value = supplied[name]
          tirs << (value ? infer_node(value, env:, self_class:) : @tir.create_integer(default, literal_type(default), span))
        end
        tirs
      end

      def infer_binding_method_call(receiver_tir, class_name, name, argument_tirs, span)
        signature = PERIPHERALS.fetch(class_name)[:methods].fetch(name)
        callee = @tir.create_callee(
          :binding_method, class_name, name, signature[:function],
          signature[:parameter_types], signature[:return_type]
        )
        @tir.create_call(receiver_tir, callee, argument_tirs, nil, signature[:return_type], span)
      end

      def infer_module_function_call(module_name, name, arguments, env:, self_class:, span:)
        signature = PERIPHERAL_MODULES.fetch(module_name).fetch(name)
        argument_tirs = arguments.map { |argument| infer_node(argument, env:, self_class:) }
        callee = @tir.create_callee(
          :binding_function, module_name, name, signature[:function],
          signature[:parameter_types], signature[:return_type]
        )
        @tir.create_call(nil, callee, argument_tirs, nil, signature[:return_type], span)
      end

      def infer_binding_function_call(name, arguments, env:, self_class:, span:)
        signature = PERIPHERAL_FUNCTIONS.fetch(name)
        argument_tirs = arguments.map { |argument| infer_node(argument, env:, self_class:) }
        callee = @tir.create_callee(
          :binding_function, nil, name, signature[:function],
          signature[:parameter_types], signature[:return_type]
        )
        @tir.create_call(nil, callee, argument_tirs, nil, signature[:return_type], span)
      end

      # ? and ! are legal in Ruby method names but not in C identifiers.
      def function_name(owner, name)
        :"#{owner}_#{name.to_s.sub(/\?\z/, '_p').sub(/!\z/, '_bang').sub(/=\z/, '_set')}"
      end

      def fixed?(type) = type == :Fixed

      # A conversion whose source already has the target type is the identity.
      def infer_conversion_call(name, receiver_tir, receiver_type, span)
        conversion = CONVERSIONS.fetch(name)
        return receiver_tir if receiver_type == conversion[:return_type]
        return to_fixed(receiver_tir) if name == :to_fixed

        callee = @tir.create_callee(
          :builtin_function, nil, name, conversion[:function], [receiver_type], conversion[:return_type]
        )
        @tir.create_call(nil, callee, [receiver_tir], nil, conversion[:return_type], span)
      end

      # The builtin signature table for Fixed (LANGUAGE.md section 5.4): an integer
      # operand is converted with to_fixed semantics, add and subtract act directly on
      # the Q16.16 representation, and multiply and divide go through the runtime so the
      # doubled intermediate, the rounding and the saturation all happen there.
      def infer_fixed_operator_call(name, receiver_tir, argument_tirs, span)
        receiver = to_fixed(receiver_tir)
        arguments = argument_tirs.map { |argument| to_fixed(argument) }

        return infer_fixed_runtime_call(name, receiver, arguments, span) if %i[* /].include?(name)

        result_type = COMPARISON_OPERATORS.include?(name) ? :Bool : :Fixed
        callee = @tir.create_callee(:builtin_operator, nil, name, nil, argument_types(arguments), result_type)
        @tir.create_call(receiver, callee, arguments, nil, result_type, span)
      end

      def infer_fixed_runtime_call(name, receiver, arguments, span)
        function = name == :* ? :bareruby_fixed_mul : :bareruby_fixed_div
        callee = @tir.create_callee(:builtin_function, nil, name, function, %i[Fixed Fixed], :Fixed)
        @tir.create_call(nil, callee, [receiver] + arguments, nil, :Fixed, span)
      end

      def to_fixed(node)
        return node if fixed?(@tir.value_type(node))

        if @tir.node_type(node) == :integer
          return @tir.create_integer(@tir.children_of(node)[0] * FIXED_ONE, :Fixed, @tir.span_of(node))
        end

        callee = @tir.create_callee(
          :builtin_function, nil, :to_fixed, :bareruby_int32_to_fixed, %i[Int32], :Fixed
        )
        @tir.create_call(nil, callee, [node], nil, :Fixed, @tir.span_of(node))
      end

      def operator?(name)
        UNARY_OPERATORS.include?(name) || BINARY_OPERATORS.include?(name) ||
          COMPARISON_OPERATORS.include?(name) || name == :!
      end

      def infer_operator_call(name, receiver_tir, receiver_type, arguments, env:, self_class:, span:)
        argument_tirs = arguments.map { |argument| infer_node(argument, env:, self_class:) }
        if fixed?(receiver_type) || argument_tirs.any? { |a| fixed?(@tir.value_type(a)) }
          return infer_fixed_operator_call(name, receiver_tir, argument_tirs, span)
        end

        result_type =
          if COMPARISON_OPERATORS.include?(name) || name == :!
            :Bool
          elsif UNARY_OPERATORS.include?(name)
            receiver_type
          else
            widen(receiver_type, @tir.value_type(argument_tirs.first))
          end
        callee = @tir.create_callee(:builtin_operator, nil, name, nil, argument_types(argument_tirs), result_type)
        @tir.create_call(receiver_tir, callee, argument_tirs, nil, result_type, span)
      end

      def infer_iterator_call(name, receiver_tir, receiver_type, arguments, block, env:, self_class:, span:)
        argument_tirs = arguments.map { |argument| infer_node(argument, env:, self_class:) }
        element_type = name == :upto ? widen(receiver_type, @tir.value_type(argument_tirs.first)) : receiver_type
        block_tir = block && infer_iterator_block(block, element_type, env:, self_class:)
        callee = @tir.create_callee(:builtin_iterator, nil, name, nil, argument_types(argument_tirs), :Nil)
        @tir.create_call(receiver_tir, callee, argument_tirs, block_tir, :Nil, span)
      end

      def infer_loop_call(block, env:, self_class:, span:)
        block_tir = block && infer_iterator_block(block, nil, env:, self_class:)
        callee = @tir.create_callee(:builtin_iterator, nil, :loop, nil, [], :Nil)
        @tir.create_call(nil, callee, [], block_tir, :Nil, span)
      end

      # puts is expanded at compile time: an interpolation becomes a format string plus
      # its values, with no intermediate buffer (LANGUAGE.md section 5.9).
      def infer_puts_call(arguments, env:, self_class:, span:)
        argument = arguments.first
        return infer_printf_call(:bareruby_printf, nil, argument, env:, self_class:, span:) if formatted?(argument)

        argument_tirs = arguments.map { |a| infer_node(a, env:, self_class:) }
        callee = @tir.create_callee(
          :builtin_puts, nil, :puts, puts_function(argument_tirs), argument_types(argument_tirs), :Nil
        )
        @tir.create_call(nil, callee, argument_tirs, nil, :Nil, span)
      end

      def formatted?(node)
        return false if node.nil?

        @bareruby_ast.node_type(node) == :interpolation
      end

      def infer_printf_call(function, receiver_tir, node, env:, self_class:, span:)
        parts = @bareruby_ast.children_of(node)[0].map { |part| infer_node(part, env:, self_class:) }
        format = +""
        values = []
        parts.each do |part|
          if @tir.node_type(part) == :string
            format << escape_format(@tir.children_of(part)[0])
          else
            format << conversion_of(@tir.value_type(part))
            values << to_s_of(part)
          end
        end
        format << "\n"

        arguments = [@tir.create_string(format, :String, span_of(node))] + values
        kind = receiver_tir ? :binding_printf : :builtin_printf
        callee = @tir.create_callee(kind, nil, :printf, function, argument_types(arguments), :Nil)
        @tir.create_call(receiver_tir, callee, arguments, nil, :Nil, span)
      end

      def escape_format(text) = text.gsub("%", "%%")

      def conversion_of(type)
        case type
        when :Int64 then "%lld"
        when :String, :Bool, :Fixed then "%s"
        else "%d"
        end
      end

      # Bool and Fixed have no printf conversion of their own, so to_s is a real call.
      TO_S_FUNCTIONS = { Bool: :bareruby_bool_to_s, Fixed: :bareruby_fixed_to_s }.freeze

      def to_s_of(part)
        function = TO_S_FUNCTIONS[@tir.value_type(part)]
        return part unless function

        callee = @tir.create_callee(
          :builtin_function, nil, :to_s, function, [@tir.value_type(part)], :String
        )
        @tir.create_call(nil, callee, [part], nil, :String, @tir.span_of(part))
      end

      def infer_iterator_block(block_node, element_type, env:, self_class:)
        parameters, body = @bareruby_ast.children_of(block_node)
        block_env = env.dup
        bindings = parameters.map do |parameter|
          @tir.create_binding(:local, @bareruby_ast.children_of(parameter)[0])
        end
        bindings.each { |binding| block_env[binding[:name]] = [binding, element_type] }
        typed_body = infer_body(body, env: block_env, self_class:)
        typed_parameters = bindings.zip(parameters).map do |binding, parameter|
          @tir.create_parameter(binding, element_type, span_of(parameter))
        end
        @tir.create_block(typed_parameters, typed_body, :Nil, span_of(block_node))
      end

      def argument_types(argument_tirs) = argument_tirs.map { |argument| @tir.value_type(argument) }

      def puts_function(argument_tirs)
        case @tir.value_type(argument_tirs.first)
        when :Int64 then :bareruby_puts_int64
        when :String then :bareruby_puts_string
        when :Bool then :bareruby_puts_bool
        when :Fixed then :bareruby_puts_fixed
        else :bareruby_puts_int32
        end
      end

      def literal_type(value)
        width = INTEGER_WIDTHS.find { |candidate| INTEGER_RANGES.fetch(candidate).cover?(value) }
        widen(width, :Int32)
      end

      def widen(left, right)
        INTEGER_WIDTHS[[INTEGER_WIDTHS.index(left), INTEGER_WIDTHS.index(right)].max]
      end

      def unify(left, right)
        return right if left == :NoReturn
        return left if right == :NoReturn

        left == right ? left : widen(left, right)
      end

      def span_of(node) = @bareruby_ast.span_of(node)
    end
  end
end
