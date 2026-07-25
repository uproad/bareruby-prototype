# frozen_string_literal: true

require_relative "../ir/tir"

module BareRubyProt
  module Pass
    class TypeInferrer
      RECEIVER_ITERATOR_NAMES = %i[times upto].freeze
      SIZE_NAMES = %i[size length].freeze
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

      # One-hot, matching PicoRuby. A direction constant of 0 would make "IN" and "no
      # direction given" the same value, so the mandatory-direction check the standard
      # guideline requires could not be expressed at all.
      GPIO_DIRECTION_MASK = 0b111

      PERIPHERAL_CLASSES = {
        GPIO: {
          struct: :bareruby_gpio_t,
          constants: { IN: 1, OUT: 2, HIGH_Z: 4, PULL_UP: 8, PULL_DOWN: 16, OPEN_DRAIN: 32 },
          constructor: { function: :bareruby_gpio_init, parameter_types: %i[Int32 Int32] },
          methods: {
            write: { function: :bareruby_gpio_write, parameter_types: %i[Int32], return_type: :Nil },
            read: { function: :bareruby_gpio_read, parameter_types: [], return_type: :Int32 },
            high?: { function: :bareruby_gpio_high, parameter_types: [], return_type: :Bool },
            low?: { function: :bareruby_gpio_low, parameter_types: [], return_type: :Bool }
          }
        }
      }.freeze

      # The guideline returns a Float from read_voltage, but Fixed is the default
      # fractional type here, so the binding returns Fixed. Q16.16 resolves to 1/65536 V,
      # finer than the 12-bit converter's least significant bit.
      ADC_CHANNEL_PINS = (26..29).freeze

      PERIPHERAL_CLASSES_EXTRA = {
        ADC: {
          struct: :bareruby_adc_t,
          constants: {},
          constructor: { function: :bareruby_adc_init, parameter_types: %i[Int32] },
          methods: {
            read: { function: :bareruby_adc_read, parameter_types: [], return_type: :Fixed },
            read_voltage: { function: :bareruby_adc_read, parameter_types: [], return_type: :Fixed },
            read_raw: { function: :bareruby_adc_read_raw, parameter_types: [], return_type: :Int32 }
          }
        },
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

      ClassInfo = Struct.new(:sources, :methods, :ivars)
      MethodInfo = Struct.new(
        :owner, :name, :parameters, :body,
        :parameter_types, :return_type, :parameter_bindings, :typed_body, :ancestor, :depth
      )

      attr_reader :result

      def initialize(bareruby_ast)
        @bareruby_ast = bareruby_ast
        @tir = TIR.new
        @classes = {}
        @modules = {}
        @class_bodies = {}
        @current_method = nil
      end

      def run
        @rescues_present = contains_begin?(@bareruby_ast.program_body)
        @constant_locals = collect_constant_locals
        register_builtin_classes
        register_classes(@bareruby_ast.program_body)

        env = {}
        typed = @bareruby_ast.program_body.map do |statement|
          definition?(statement) ? statement : infer_node(statement, env:, self_class: nil)
        end

        body = @bareruby_ast.program_body.zip(typed).filter_map do |original, typed_statement|
          next if module_definition?(original)

          class_definition?(original) ? build_class_definition(original) : typed_statement
        end

        @result = @tir.replace_program(body)

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

      def class_definition?(node) = @bareruby_ast.node_type(node) == :class_definition

      def register_builtin_classes
        @classes[:BasicObject] = ClassInfo.new([], {}, {})
        initialize_info = MethodInfo.new(:Object, :initialize, [], [], [], :Nil, [], [], nil, 0)
        @classes[:Object] = ClassInfo.new([:BasicObject], { initialize: initialize_info }, {})
      end

      def module_definition?(node) = @bareruby_ast.node_type(node) == :module_definition

      def register_classes(statements)
        statements.each do |statement|
          @modules[member_name(statement)] = statement if module_definition?(statement)
          @class_bodies[member_name(statement)] = statement if class_definition?(statement)
        end
        statements.each { |statement| register_class(statement) if class_definition?(statement) }
      end

      def member_name(node)
        module_definition?(node) || class_definition?(node) ? @bareruby_ast.children_of(node)[0] : nil
      end

      # Inheritance and include are the same mechanism: compile-time flat expansion.
      # Pass 2 already turned the superclass into a leading include, so a class body is a
      # list of include calls followed by its own
      # definitions. Later sources win over earlier ones and the class's own definitions
      # win over all of them. Every definition is copied into the class, which is what
      # lets an included method infer instance variables against the including class.
      def register_class(node)
        name, body = @bareruby_ast.children_of(node)
        definitions = expand(body)

        # Every class descends from Object, whose initialize takes no arguments and
        # assigns nothing. It is the base of every chain, so a
        # class without its own initialize still has one and super always has a floor.
        methods = { initialize: MethodInfo.new(name, :initialize, [], [], [], :Nil, [], [], nil, 0) }
        definitions.each do |definition|
          method_name, parameters, method_body = @bareruby_ast.children_of(definition)
          info = MethodInfo.new(name, method_name, parameters, method_body, nil, nil, nil, nil, nil, 0)
          info.ancestor = methods[method_name]
          methods[method_name] = info
        end
        methods.each_value { |info| number_chain(info) }

        @classes[name] = ClassInfo.new(included_names(body), methods, {})
      end

      # The winner is depth 0; each definition it shadowed sits one deeper, which is
      # what super walks and what keeps the generated function names apart.
      def number_chain(info)
        depth = 0
        while info
          info.depth = depth
          depth += 1
          info = info.ancestor
        end
      end

      def definition?(node) = class_definition?(node) || module_definition?(node)

      # The definitions a body contributes, ancestors first. A class source expands
      # transitively, so a chain of classes flattens in one pass.
      def expand(body)
        included_names(body).flat_map { |source| expand_source(source) } +
          body.select { |member| @bareruby_ast.node_type(member) == :method_definition }
      end

      def expand_source(source)
        definition = @modules[source] || @class_bodies[source]
        definition ? expand(@bareruby_ast.children_of(definition)[1]) : []
      end

      def included_names(body)
        body.select { |member| include_call?(member) }.map { |member| included_name(member) }
      end

      def include_call?(node)
        return false unless @bareruby_ast.node_type(node) == :call

        receiver, call_name, = @bareruby_ast.children_of(node)
        receiver.nil? && call_name == :include
      end

      def included_name(node)
        @bareruby_ast.children_of(@bareruby_ast.children_of(node)[2].first)[1]
      end

      def find_method(class_name, name)
        @classes.fetch(class_name).methods[name]
      end

      # Every definition the class flattened is emitted, including the ones a subclass
      # or a later include shadowed, because super still reaches them.
      def build_class_definition(node)
        name, = @bareruby_ast.children_of(node)
        class_info = @classes.fetch(name)
        methods = class_info.methods.values.flat_map { |info| chain_of(info) }
                            .filter_map { |info| build_method_definition(info) }
        ivars = class_info.ivars.map { |ivar_name, type| { name: ivar_name, type: } }
        @tir.create_class_definition(name, ivars, methods, span_of(node))
      end

      def chain_of(info)
        chain = []
        while info
          chain << info
          info = info.ancestor
        end
        chain
      end

      def build_method_definition(method_info)
        return unless method_info.return_type

        identity = @tir.create_identity(
          method_info.owner, method_name_at(method_info), method_info.parameter_types, method_info.return_type
        )
        typed_parameters = method_info.parameter_bindings.zip(method_info.parameters, method_info.parameter_types)
                                     .map { |binding, parameter, type| @tir.create_parameter(binding, type, span_of(parameter)) }
        @tir.create_method_definition(identity, typed_parameters, method_info.typed_body, nil)
      end

      # A shadowed definition needs a name of its own in the generated code.
      def method_name_at(info) = info.depth.zero? ? info.name : :"#{info.name}__super#{info.depth}"

      def resolve_method_call(method_info, argument_types)
        infer_method!(method_info, argument_types) if method_info.return_type.nil?
        method_info
      end

      def infer_method!(method_info, argument_types)
        bindings = method_info.parameters.map do |parameter|
          @tir.create_binding(:local, @bareruby_ast.children_of(parameter)[0])
        end
        env = bindings.each_with_index.to_h { |binding, index| [binding[:name], [binding, argument_types[index]]] }
        # Recorded before the body is inferred, because a bare super inside it forwards
        # these very parameters.
        method_info.parameter_types = argument_types
        method_info.parameter_bindings = bindings

        enclosing = @current_method
        @current_method = method_info
        typed_body = infer_body(method_info.body, env:, self_class: method_info.owner)
        @current_method = enclosing

        method_info.typed_body = typed_body
        method_info.return_type =
          method_info.name == :initialize ? :Nil : method_return_type(typed_body)
      end

      # Every return in the body contributes, plus the value the body falls off the end
      # with. NoReturn contributes nothing.
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
        when :super then infer_super(node, env:, self_class:)
        when :begin then infer_begin(node, env:, self_class:)
        when :constant_path then infer_constant_path(node)
        when :if then infer_if(node, env:, self_class:)
        when :while then infer_while(node, env:, self_class:)
        when :logical then infer_logical(node, env:, self_class:)
        when :reference then infer_reference(node, env:, self_class:)
        when :assignment then infer_assignment(node, env:, self_class:)
        when :array then infer_array(node, env:, self_class:)
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
      # time and carried as its internal integer form.
      def infer_float(node)
        value = @bareruby_ast.children_of(node)[0]
        @tir.create_integer((value * FIXED_ONE).round, :Fixed, span_of(node))
      end

      # begin/rescue lowers to try/catch. Only the untyped rescue form is handled: an
      # exception class hierarchy is still undecided, so nothing here invents one.
      def infer_begin(node, env:, self_class:)
        body, rescue_body = @bareruby_ast.children_of(node)
        @tir.create_begin(
          infer_body(body, env:, self_class:), infer_body(rescue_body, env:, self_class:), span_of(node)
        )
      end

      # raise degrades to panic when the program has no begin at all, and throws
      # otherwise. Only the string form is accepted; the other forms are not settled.
      def infer_raise_call(arguments, env:, self_class:, span:)
        argument_tirs = arguments.map { |argument| infer_node(argument, env:, self_class:) }
        function = @rescues_present ? :bareruby_throw : :bareruby_panic
        callee = @tir.create_callee(:builtin_function, nil, :raise, function, %i[String], :NoReturn)
        @tir.create_call(nil, callee, argument_tirs, nil, :NoReturn, span)
      end

      # super is a static call to the definition this one shadowed. No arguments means
      # forward the ones the method received.
      def infer_super(node, env:, self_class:)
        ancestor = @current_method.ancestor
        arguments = @bareruby_ast.children_of(node)[0]
        argument_tirs =
          if arguments.empty?
            @current_method.parameter_bindings.zip(@current_method.parameter_types)
                           .map { |binding, type| @tir.create_reference(binding, type, span_of(node)) }
          else
            arguments.map { |argument| infer_node(argument, env:, self_class:) }
          end

        resolved = resolve_method_call(ancestor, argument_types(argument_tirs))
        callee = @tir.create_callee(
          :user_method, resolved.owner, resolved.name,
          function_name(resolved.owner, method_name_at(resolved)),
          resolved.parameter_types, resolved.return_type
        )
        @tir.create_call(nil, callee, argument_tirs, nil, resolved.return_type, span_of(node))
      end

      def infer_symbol(node)
        @tir.create_symbol(@bareruby_ast.children_of(node)[0], :Symbol, span_of(node))
      end

      # The element type is the least upper bound of the elements, so a literal that mixes
      # types with no common widening is an error here rather than something the backend
      # has to represent.
      def infer_array(node, env:, self_class:)
        elements = @bareruby_ast.children_of(node)[0].map do |element|
          infer_node(element, env:, self_class:)
        end
        types = argument_types(elements)
        unless types.uniq.one? || types.all? { |element| INTEGER_WIDTHS.include?(element) }
          raise "array literal mixes #{types.uniq.join(' and ')}, which have no common type"
        end

        type = @tir.create_array_type(types.reduce { |left, right| unify(left, right) }, elements.length)
        @tir.create_array(elements, type, span_of(node))
      end

      # The capacity must be settled while compiling. The initial value may be left out, in
      # which case the storage is not written and the element type comes from the first
      # assignment instead.
      def infer_array_new_call(arguments, env:, self_class:, span:)
        capacity = constant_capacity(arguments[0], env:, self_class:)
        raise "Array.new: the capacity must be known at compile time" if capacity.nil?
        return @tir.create_array_fill(nil, @tir.create_array_type(nil, capacity), span) if arguments.length < 2

        value = infer_node(arguments[1], env:, self_class:)
        @tir.create_array_fill(value, @tir.create_array_type(@tir.value_type(value), capacity), span)
      end

      def constant_capacity(node, env:, self_class:)
        return nil if node.nil?
        return @constant_locals[@bareruby_ast.children_of(node)[1]] if reference_to_local?(node)

        constant_integer(infer_node(node, env:, self_class:))
      end

      def reference_to_local?(node)
        @bareruby_ast.node_type(node) == :reference &&
          @bareruby_ast.children_of(node)[0] == :local
      end

      def infer_string(node)
        @tir.create_string(@bareruby_ast.children_of(node)[0], :String, span_of(node))
      end

      # An if in value position takes the type both branches agree on; as a statement it
      # is Nil. A missing else keeps it a statement. A branch that always leaves
      # contributes NoReturn, which the other branch absorbs.
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
        value_tir =
          if @bareruby_ast.node_type(value) == :interpolation
            infer_format(value, env:, self_class:)
          else
            infer_node(value, env:, self_class:)
          end
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
          when :raise then infer_raise_call(arguments, env:, self_class:, span:)
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
          if class_name == :Array
            infer_array_new_call(arguments, env:, self_class:, span:)
          elsif PERIPHERALS.key?(class_name)
            infer_binding_new_call(class_name, arguments, env:, self_class:, span:)
          else
            infer_new_call(class_name, arguments, env:, self_class:, span:)
          end
        else
          receiver_tir = infer_node(receiver, env:, self_class:)
          receiver_type = @tir.value_type(receiver_tir)

          if array_type?(receiver_type)
            infer_array_method_call(name, receiver_tir, receiver_type, arguments, env:, self_class:, span:)
          elsif CONVERSIONS.key?(name)
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

      def array_type?(type) = type.is_a?(Hash) && type[:kind] == :array

      # size folds to the capacity because a fixed-capacity array can have no other length
      # Indexing is pointer arithmetic and is not range checked, at compile time or at run
      # time; a negative index is out of range like any other and is left alone.
      def infer_array_method_call(name, receiver_tir, receiver_type, arguments, env:, self_class:, span:)
        return @tir.create_array_dup(receiver_tir, receiver_type, span) if name == :dup

        capacity = receiver_type[:capacity]
        return @tir.create_integer(capacity, literal_type(capacity), span) if SIZE_NAMES.include?(name)

        index = infer_node(arguments[0], env:, self_class:)
        return infer_index_assign(receiver_tir, receiver_type, index, arguments[1], env:, self_class:, span:) if name == :[]=

        element_type = receiver_type[:element]
        raise "the element type of this array is not known yet" if element_type.nil?

        @tir.create_index(receiver_tir, index, element_type, span)
      end

      # Array.new(n) leaves the element type open, and the first assignment settles it
      # The type hash is shared with every reference to the array, so filling it in here
      # reaches all of them.
      def infer_index_assign(receiver_tir, receiver_type, index, value_node, env:, self_class:, span:)
        value = infer_node(value_node, env:, self_class:)
        receiver_type[:element] ||= @tir.value_type(value)
        @tir.create_index_assign(receiver_tir, index, value, receiver_type[:element], span)
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
        verify_gpio_direction(argument_tirs) if class_name == :GPIO
        verify_adc_pin(argument_tirs) if class_name == :ADC
        instance_type = @tir.create_instance_type(class_name, peripheral[:struct])
        callee = @tir.create_callee(
          :binding_new, class_name, :new, constructor[:function],
          argument_types(argument_tirs), instance_type
        )
        @tir.create_call(nil, callee, argument_tirs, nil, instance_type, span)
      end

      # Exactly one of IN / OUT / HIGH_Z is mandatory. The standard guideline raises
      # ArgumentError at run time; one-hot constants let us fold the params expression and
      # reject it while compiling instead.
      def verify_gpio_direction(argument_tirs)
        params = constant_integer(argument_tirs[1])
        return if params.nil?

        directions = (params & GPIO_DIRECTION_MASK).digits(2).count(1)
        return if directions == 1

        raise "GPIO.new: params must name exactly one of GPIO::IN, GPIO::OUT and GPIO::HIGH_Z"
      end

      # Pins without a converter channel are rejected while compiling.
      def verify_adc_pin(argument_tirs)
        pin = constant_integer(argument_tirs[0])
        return if pin.nil? || ADC_CHANNEL_PINS.include?(pin)

        raise "ADC.new: pin #{pin} has no converter channel (expected #{ADC_CHANNEL_PINS})"
      end

      def constant_integer(node)
        return nil if node.nil?
        return @tir.children_of(node)[0] if @tir.node_type(node) == :integer
        return nil unless @tir.node_type(node) == :call

        receiver, callee, arguments = @tir.children_of(node)
        return nil unless callee[:kind] == :builtin_operator && callee[:name] == :|

        left = constant_integer(receiver)
        right = constant_integer(arguments[0])
        left && right && (left | right)
      end

      # A fixed key set: every declared keyword becomes a
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

      # The builtin signature table for Fixed: an integer
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
      # its values, with no intermediate buffer.
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

      # Widest rendering of each type, used to size the temporary buffer an interpolation
      # assigns into. A String of unknown capacity has no honest bound here; a real
      # implementation would carry the capacity in the type, so this is the one number in
      # the estimate that is a placeholder rather than a derivation.
      MAX_LENGTHS = { Int32: 11, Int64: 20, Bool: 5, Fixed: 12, String: 64 }.freeze

      # An interpolation outside a puts argument becomes a fixed-capacity buffer plus a
      # compile-time bound on what can land in it.
      def infer_format(node, env:, self_class:)
        parts = @bareruby_ast.children_of(node)[0].map { |part| infer_node(part, env:, self_class:) }
        format = +""
        values = []
        capacity = 1

        parts.each do |part|
          if @tir.node_type(part) == :string
            text = @tir.children_of(part)[0]
            format << escape_format(text)
            capacity += text.bytesize
          else
            format << conversion_of(@tir.value_type(part))
            capacity += MAX_LENGTHS.fetch(@tir.value_type(part), 32)
            values << to_s_of(part)
          end
        end

        @tir.create_format(
          capacity, @tir.create_string(format, :String, span_of(node)), values, :String, span_of(node)
        )
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
