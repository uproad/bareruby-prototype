# frozen_string_literal: true

require_relative "../ir/typed_ast"
require_relative "pass_05_type_inferrer/arena"
require_relative "pass_05_type_inferrer/arena_string"
require_relative "pass_05_type_inferrer/arena_array"

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
          constants: { IN: 1, OUT: 2, HIGH_Z: 4, PULL_UP: 8, PULL_DOWN: 16, OPEN_DRAIN: 32, EDGE_FALL: 4 },
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

      # The on-board LED is its own class rather than a GPIO with a known pin, because on
      # a board that has one it is frequently not a GPIO at all — a Pico W drives its LED
      # through the wireless chip, and GP25, where the plain Pico's LED sits, is that
      # chip's select line instead. Sharing GPIO's interface would only hide that. Which
      # board the program is being built for decides how the binding reaches it, so a
      # program that blinks says nothing about the board it will run on.
      PERIPHERAL_CLASSES_ONBOARD = {
        OnboardLED: {
          struct: :bareruby_onboard_led_t,
          constants: {},
          constructor: { function: :bareruby_onboard_led_init, parameter_types: [] },
          methods: {
            write: { function: :bareruby_onboard_led_write, parameter_types: %i[Int32], return_type: :Nil },
            on: { function: :bareruby_onboard_led_on, parameter_types: [], return_type: :Nil },
            off: { function: :bareruby_onboard_led_off, parameter_types: [], return_type: :Nil }
          }
        }
      }.freeze

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
            read: { function: :bareruby_uart_read, parameter_types: %i[Int32], return_type: :arena_string },
            gets: { function: :bareruby_uart_gets, parameter_types: [], return_type: :arena_string },
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
        },
        I2C: {
          struct: :bareruby_i2c_t,
          constants: {},
          constructor: {
            function: :bareruby_i2c_init,
            parameter_types: %i[Int32],
            keywords: { frequency: 100_000 }
          },
          methods: {
            write: { function: :bareruby_i2c_write, parameter_types: [], return_type: :Int32 },
            read: { function: :bareruby_i2c_read, parameter_types: [], return_type: :arena_string }
          }
        }
      }.freeze

      # sleep waits from the moment it is called, so a loop drifts by however long its
      # body takes. asleep waits from the moment the previous asleep returned, which is
      # what a loop that has to keep a period needs.
      PERIPHERAL_FUNCTIONS = {
        sleep: { function: :bareruby_sleep, parameter_types: %i[Int32], return_type: :Nil },
        sleep_ms: { function: :bareruby_sleep_ms, parameter_types: %i[Int32], return_type: :Nil },
        asleep: { function: :bareruby_asleep, parameter_types: %i[Int32], return_type: :Nil },
        asleep_ms: { function: :bareruby_asleep_ms, parameter_types: %i[Int32], return_type: :Nil },
        asleep_us: { function: :bareruby_asleep_us, parameter_types: %i[Int32], return_type: :Nil }
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

      PERIPHERALS =
        PERIPHERAL_CLASSES.merge(PERIPHERAL_CLASSES_EXTRA, PERIPHERAL_CLASSES_ONBOARD).freeze

      ClassInfo = Struct.new(:sources, :methods, :ivars, :initialized_ivars)
      MethodInfo = Struct.new(
        :owner, :name, :parameters, :body,
        :parameter_types, :return_type, :parameter_bindings, :typed_body, :ancestor, :depth
      )

      attr_reader :result

      def initialize(bareruby_ast)
        @bareruby_ast = bareruby_ast
        @tast = TypedAST.new
        @classes = {}
        @modules = {}
        @class_bodies = {}
        @current_method = nil
        @arena = nil
      end

      def run
        @rescues_present = contains_begin?(@bareruby_ast.program_body)
        @constant_locals = collect_constant_locals
        register_builtin_classes
        register_classes(@bareruby_ast.program_body)

        @local_bindings = {}
        env = {}
        typed = @bareruby_ast.program_body.map do |statement|
          definition?(statement) ? statement : infer_node(statement, env:, self_class: nil)
        end

        body = @bareruby_ast.program_body.zip(typed).filter_map do |original, typed_statement|
          next if module_definition?(original)

          class_definition?(original) ? build_class_definition(original) : typed_statement
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

      def class_definition?(node) = @bareruby_ast.node_type(node) == :class_definition

      def register_builtin_classes
        @classes[:BasicObject] = ClassInfo.new([], {}, {}, [])
        initialize_info = MethodInfo.new(:Object, :initialize, [], [], [], :Nil, [], [], nil, 0)
        @classes[:Object] = ClassInfo.new([:BasicObject], { initialize: initialize_info }, {}, [])
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

        @classes[name] = ClassInfo.new(included_names(body), methods, {}, [])
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
        @tast.create_class_definition(name, ivars, methods, span_of(node))
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

        identity = @tast.create_identity(
          method_info.owner, method_name_at(method_info), method_info.parameter_types, method_info.return_type
        )
        typed_parameters = method_info.parameter_bindings.zip(method_info.parameters, method_info.parameter_types)
                                     .map { |binding, parameter, type| @tast.create_parameter(binding, type, span_of(parameter)) }
        @tast.create_method_definition(identity, typed_parameters, method_info.typed_body, nil)
      end

      # A shadowed definition needs a name of its own in the generated code.
      def method_name_at(info) = info.depth.zero? ? info.name : :"#{info.name}__super#{info.depth}"

      def resolve_method_call(method_info, argument_types)
        infer_method!(method_info, argument_types) if method_info.return_type.nil?
        method_info
      end

      def infer_method!(method_info, argument_types)
        enclosing_bindings = @local_bindings
        @local_bindings = {}
        bindings = method_info.parameters.each_with_index.map do |parameter, index|
          @tast.create_binding(:local, @bareruby_ast.children_of(parameter)[0], argument_types[index])
        end
        bindings.each { |binding| @local_bindings[binding[:name]] = binding }
        env = bindings.each_with_index.to_h { |binding, index| [binding[:name], [binding, argument_types[index]]] }
        # Recorded before the body is inferred, because a bare super inside it forwards
        # these very parameters.
        method_info.parameter_types = argument_types
        method_info.parameter_bindings = bindings

        enclosing = @current_method
        @current_method = method_info
        typed_body = infer_body(method_info.body, env:, self_class: method_info.owner)
        finalize_initialize_ivars(method_info.owner, typed_body) if method_info.name == :initialize
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
        class_info = @classes.fetch(owner)
        class_info.initialized_ivars |= definitely_assigned_ivars(typed_body)
        class_info.ivars.each do |name, type|
          class_info.ivars[name] = unify(:Nil, type) unless class_info.initialized_ivars.include?(name)
        end
        annotate_ivar_storage_types!(typed_body, class_info.ivars)
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
          else
            current
          end
        end
      end

      def annotate_ivar_storage_types!(value, ivars)
        return value.each { |element| annotate_ivar_storage_types!(element, ivars) } if value.is_a?(Array)
        return unless value.is_a?(Hash) && value.key?(:children)

        if %i[assignment reference].include?(@tast.node_type(value))
          binding = @tast.children_of(value)[0]
          if binding[:kind] == :instance && ivars.key?(binding[:name])
            binding[:type] = ivars.fetch(binding[:name])
          end
        end
        annotate_ivar_storage_types!(value[:children], ivars)
      end

      # Every return in the body contributes, plus the value the body falls off the end
      # with. NoReturn contributes nothing.
      def method_return_type(typed_body)
        return :Nil if typed_body.empty?

        types = collect_return_types(typed_body)
        types << @tast.value_type(typed_body.last) unless terminator?(typed_body.last)
        types = types.reject { |type| type == :NoReturn }
        types.empty? ? :Nil : types.reduce { |left, right| unify(left, right) }
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

      def infer_body(statements, env:, self_class:)
        statements.map { |statement| infer_node(statement, env:, self_class:) }
      end

      def infer_node(node, env:, self_class:)
        case @bareruby_ast.node_type(node)
        when :integer then infer_integer(node)
        when :nil then @tast.create_nil(span_of(node))
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
        @tast.create_integer(value, literal_type(value), span_of(node))
      end

      def infer_boolean(node)
        @tast.create_boolean(@bareruby_ast.children_of(node)[0], :Bool, span_of(node))
      end

      # A decimal literal is rounded to the nearest representable Q16.16 value at compile
      # time and carried as its internal integer form.
      def infer_float(node)
        value = @bareruby_ast.children_of(node)[0]
        @tast.create_integer((value * FIXED_ONE).round, :Fixed, span_of(node))
      end

      # begin/rescue lowers to try/catch. Only the untyped rescue form is handled: an
      # exception class hierarchy is still undecided, so nothing here invents one.
      def infer_begin(node, env:, self_class:)
        body, rescue_body = @bareruby_ast.children_of(node)
        @tast.create_begin(
          infer_body(body, env:, self_class:), infer_body(rescue_body, env:, self_class:), span_of(node)
        )
      end

      # raise degrades to panic when the program has no begin at all, and throws
      # otherwise. Only the string form is accepted; the other forms are not settled.
      def infer_raise_call(arguments, env:, self_class:, span:)
        argument_tasts = arguments.map { |argument| string_value_of(infer_node(argument, env:, self_class:)) }
        function = @rescues_present ? :bareruby_throw : :bareruby_panic
        callee = @tast.create_callee(:builtin_function, nil, :raise, function, %i[String], :NoReturn)
        @tast.create_call(nil, callee, argument_tasts, nil, :NoReturn, span)
      end

      # super is a static call to the definition this one shadowed. No arguments means
      # forward the ones the method received.
      def infer_super(node, env:, self_class:)
        ancestor = @current_method.ancestor
        arguments = @bareruby_ast.children_of(node)[0]
        argument_tasts =
          if arguments.empty?
            @current_method.parameter_bindings.zip(@current_method.parameter_types)
                           .map { |binding, type| @tast.create_reference(binding, type, span_of(node)) }
          else
            arguments.map { |argument| infer_node(argument, env:, self_class:) }
          end

        resolved = resolve_method_call(ancestor, argument_types(argument_tasts))
        callee = @tast.create_callee(
          :user_method, resolved.owner, resolved.name,
          function_name(resolved.owner, method_name_at(resolved)),
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
      def infer_array(node, env:, self_class:)
        elements = @bareruby_ast.children_of(node)[0].map do |element|
          infer_node(element, env:, self_class:)
        end
        types = argument_types(elements)
        unless types.uniq.one? || types.all? { |element| INTEGER_WIDTHS.include?(element) }
          raise "array literal mixes #{types.uniq.join(' and ')}, which have no common type"
        end

        type = @tast.create_array_type(types.reduce { |left, right| unify(left, right) }, elements.length)
        @tast.create_array(elements, type, span_of(node))
      end

      # The capacity must be settled while compiling. The initial value may be left out, in
      # which case the storage is not written and the element type comes from the first
      # assignment instead.
      def infer_array_new_call(arguments, env:, self_class:, span:)
        capacity = constant_capacity(arguments[0], env:, self_class:)
        raise "Array.new: the capacity must be known at compile time" if capacity.nil?
        return @tast.create_array_fill(nil, @tast.create_array_type(nil, capacity), span) if arguments.length < 2

        value = infer_node(arguments[1], env:, self_class:)
        @tast.create_array_fill(value, @tast.create_array_type(@tast.value_type(value), capacity), span)
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
        @tast.create_string(@bareruby_ast.children_of(node)[0], :String, span_of(node))
      end

      # A missing else is the Nil branch. Branch-local environments preserve the
      # truthiness fact while each arm is inferred, then merge back into a T? where one
      # path has Nil or never assigned a new local.
      def infer_if(node, env:, self_class:)
        condition, then_body, else_body = @bareruby_ast.children_of(node)
        condition_tast = infer_node(condition, env:, self_class:)
        base_env = env.dup
        then_env = base_env.dup
        else_env = base_env.dup
        narrow_condition!(condition_tast, then_env, truthy: true)
        narrow_condition!(condition_tast, else_env, truthy: false)

        then_tast = infer_body(then_body, env: then_env, self_class:)
        else_tast = else_body && infer_body(else_body, env: else_env, self_class:)
        then_type = branch_type(then_tast)
        else_type = else_tast ? branch_type(else_tast) : :Nil
        merge_branch_env!(env, then_env, else_env,
                          left_reachable: then_type != :NoReturn, right_reachable: else_type != :NoReturn)
        type = unify(then_type, else_type)
        @tast.create_if(condition_tast, then_tast, else_tast, type, span_of(node))
      end

      def branch_type(statements)
        return :Nil if statements.empty?
        return :NoReturn if terminator?(statements.last)

        @tast.value_type(statements.last)
      end

      def terminator?(node) = %i[return iteration_control].include?(@tast.node_type(node))

      def infer_while(node, env:, self_class:)
        condition, body = @bareruby_ast.children_of(node)
        condition_tast = infer_node(condition, env:, self_class:)
        body_env = env.dup
        narrow_condition!(condition_tast, body_env, truthy: true)
        typed_body = infer_body(body, env: body_env, self_class:)
        narrow_condition!(condition_tast, env, truthy: false)
        merge_loop_env!(env, body_env)
        @tast.create_while(condition_tast, typed_body, span_of(node))
      end

      def infer_logical(node, env:, self_class:)
        operator, left, right = @bareruby_ast.children_of(node)
        left_tast = infer_node(left, env:, self_class:)
        right_env = env.dup
        narrow_condition!(left_tast, right_env, truthy: operator == :and)
        right_tast = infer_node(right, env: right_env, self_class:)
        left_type = @tast.value_type(left_tast)
        right_type = @tast.value_type(right_tast)
        type =
          if operator == :or && nilable_type?(left_type)
            unify(left_type[:inner], right_type)
          elsif operator == :or && left_type == :Nil
            right_type
          elsif operator == :and && nilable_type?(left_type)
            unify(:Nil, right_type)
          else
            unify(left_type, right_type)
          end
        @tast.create_logical(operator, left_tast, right_tast, type, span_of(node))
      end

      def narrow_condition!(condition, env, truthy:)
        binding, type =
          case @tast.node_type(condition)
          when :reference
            @tast.children_of(condition)
          when :assignment
            assignment_binding, _value, assignment_type = @tast.children_of(condition)
            [assignment_binding, assignment_type]
          end
        return unless binding && binding[:kind] == :local && nilable_type?(type)

        env[binding[:name]] = [binding, truthy ? type[:inner] : :Nil]
      end

      def merge_branch_env!(env, left, right, left_reachable: true, right_reachable: true)
        return env.replace(left) unless right_reachable
        return env.replace(right) unless left_reachable
        return unless left_reachable || right_reachable

        (left.keys | right.keys).each do |name|
          left_entry = left[name]
          right_entry = right[name]
          binding = (left_entry || right_entry)[0]
          type = unify(left_entry ? left_entry[1] : :Nil, right_entry ? right_entry[1] : :Nil)
          binding[:type] = binding[:type] ? unify(binding[:type], type) : type
          env[name] = [binding, type]
        end
      end

      # The body may execute zero times. Only names introduced by it need a new Nil path;
      # existing names retain the type known at loop exit, while their binding storage has
      # already absorbed any types assigned in the body.
      def merge_loop_env!(env, body_env)
        (body_env.keys - env.keys).each do |name|
          binding, body_type = body_env.fetch(name)
          type = unify(:Nil, body_type)
          binding[:type] = binding[:type] ? unify(binding[:type], type) : type
          env[name] = [binding, type]
        end
      end

      def infer_constant_path(node)
        owner, name = @bareruby_ast.children_of(node)
        value = PERIPHERALS.fetch(owner)[:constants].fetch(name)
        @tast.create_integer(value, literal_type(value), span_of(node))
      end

      def infer_reference(node, env:, self_class:)
        kind, name = @bareruby_ast.children_of(node)
        case kind
        when :local
          binding, type = env.fetch(name)
          @tast.create_reference(binding, type, span_of(node))
        when :instance
          type = @classes.fetch(self_class).ivars.fetch(name)
          binding = @tast.create_binding(:instance, name, type)
          @tast.create_reference(binding, type, span_of(node))
        end
      end

      def infer_assignment(node, env:, self_class:)
        target, value = @bareruby_ast.children_of(node)
        value_tast =
          if @bareruby_ast.node_type(value) == :interpolation
            infer_format(value, env:, self_class:)
          else
            infer_node(value, env:, self_class:)
          end
        value_type = @tast.value_type(value_tast)
        kind, name = @bareruby_ast.children_of(target)
        reject_arena_escape(kind, name, value_tast)

        binding = @tast.create_binding(kind, name)
        case kind
        when :local
          binding = @local_bindings[name] ||= binding
          binding[:type] = binding[:type] ? unify(binding[:type], value_type) : value_type
          env[name] = [binding, value_type]
        when :instance
          class_info = @classes.fetch(self_class)
          storage_type =
            if class_info.ivars.key?(name)
              unify(class_info.ivars.fetch(name), value_type)
            else
              value_type
            end
          unless @current_method&.name == :initialize || class_info.initialized_ivars.include?(name)
            storage_type = unify(:Nil, storage_type)
          end
          class_info.ivars[name] = storage_type
          binding = @tast.create_binding(:instance, name, storage_type)
        end

        @tast.create_assignment(binding, value_tast, value_type, span_of(node))
      end

      def infer_return(node, env:, self_class:)
        value = @bareruby_ast.children_of(node)[0]
        value_tast = value && infer_node(value, env:, self_class:)
        @tast.create_return(value_tast, value_tast ? @tast.value_type(value_tast) : :Nil, span_of(node))
      end

      def infer_iteration_control(node)
        @tast.create_iteration_control(@bareruby_ast.children_of(node)[0], span_of(node))
      end

      def infer_call(node, env:, self_class:)
        receiver, name, arguments, block = @bareruby_ast.children_of(node)
        span = span_of(node)

        if receiver.nil?
          case name
          when :puts then infer_puts_call(arguments, env:, self_class:, span:)
          when :loop then infer_loop_call(block, env:, self_class:, span:)
          when :raise then infer_raise_call(arguments, env:, self_class:, span:)
          when :arena then infer_arena_call(arguments, block, env:, self_class:, span:)
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
          elsif class_name == :Arena
            infer_arena_new_call(arguments, env:, self_class:, span:)
          elsif PERIPHERALS.key?(class_name)
            infer_binding_new_call(class_name, arguments, env:, self_class:, span:)
          else
            infer_new_call(class_name, arguments, env:, self_class:, span:)
          end
        else
          receiver_tast = infer_node(receiver, env:, self_class:)
          receiver_type = @tast.value_type(receiver_tast)

          if name == :nil?
            infer_nil_predicate(receiver_tast, receiver_type, span)
          elsif array_type?(receiver_type)
            infer_array_method_call(name, receiver_tast, receiver_type, arguments, env:, self_class:, span:)
          elsif ArenaArray.type?(receiver_type)
            infer_arena_array_method_call(name, receiver_tast, receiver_type, arguments, env:, self_class:, span:)
          elsif ArenaString.type?(receiver_type)
            infer_arena_string_method_call(name, receiver_tast, arguments, env:, self_class:, span:)
          elsif Arena.type?(receiver_type)
            infer_arena_method_call(name, receiver_tast, arguments, env:, self_class:, span:)
          elsif CONVERSIONS.key?(name)
            infer_conversion_call(name, receiver_tast, receiver_type, span)
          elsif operator?(name)
            infer_operator_call(name, receiver_tast, receiver_type, arguments, env:, self_class:, span:)
          elsif RECEIVER_ITERATOR_NAMES.include?(name)
            infer_iterator_call(name, receiver_tast, receiver_type, arguments, block, env:, self_class:, span:)
          elsif receiver_type.is_a?(Hash) && receiver_type[:class_name] == :GPIO && name == :on_interrupt
            infer_gpio_interrupt_call(receiver_tast, arguments, block, env:, self_class:, span:)
          else
            infer_instance_method_call(receiver_tast, receiver_type, name, arguments, env:, self_class:, span:)
          end
        end
      end

      def infer_nil_predicate(receiver_tast, receiver_type, span)
        return @tast.create_boolean(true, :Bool, span) if receiver_type == :Nil
        return @tast.create_boolean(false, :Bool, span) unless nilable_type?(receiver_type)

        callee = @tast.create_callee(:builtin_nil_p, nil, :nil?, nil, [], :Bool)
        @tast.create_call(receiver_tast, callee, [], nil, :Bool, span)
      end

      def array_type?(type) = type.is_a?(Hash) && type[:kind] == :array

      # size folds to the capacity because a fixed-capacity array can have no other length
      # Indexing is pointer arithmetic and is not range checked, at compile time or at run
      # time; a negative index is out of range like any other and is left alone.
      def infer_array_method_call(name, receiver_tast, receiver_type, arguments, env:, self_class:, span:)
        return @tast.create_array_dup(receiver_tast, receiver_type, span) if name == :dup

        capacity = receiver_type[:capacity]
        return @tast.create_integer(capacity, literal_type(capacity), span) if SIZE_NAMES.include?(name)

        index = infer_node(arguments[0], env:, self_class:)
        return infer_index_assign(receiver_tast, receiver_type, index, arguments[1], env:, self_class:, span:) if name == :[]=

        element_type = receiver_type[:element]
        raise "the element type of this array is not known yet" if element_type.nil?

        @tast.create_index(receiver_tast, index, element_type, span)
      end

      # Array.new(n) leaves the element type open, and the first assignment settles it
      # The type hash is shared with every reference to the array, so filling it in here
      # reaches all of them.
      def infer_index_assign(receiver_tast, receiver_type, index, value_node, env:, self_class:, span:)
        value = infer_node(value_node, env:, self_class:)
        receiver_type[:element] ||= @tast.value_type(value)
        @tast.create_index_assign(receiver_tast, index, value, receiver_type[:element], span)
      end

      # The region is created when the block is entered and released when it is left, so
      # its size is what the whole block may allocate and has to be settled while
      # compiling: the storage is reserved statically, not taken from a heap.
      def infer_arena_call(arguments, block, env:, self_class:, span:)
        size = constant_capacity(keyword_value(arguments, :size), env:, self_class:)
        raise "arena: the size must be known at compile time" if size.nil?

        parameters, body = @bareruby_ast.children_of(block)
        binding = @tast.create_binding(:local, @bareruby_ast.children_of(parameters.first)[0])
        block_env = env.merge(binding[:name] => [binding, Arena.type(@tast)])

        typed_body = inside_arena(Arena.new(binding, enclosing: @arena, outer_names: env.keys)) do
          infer_body(body, env: block_env, self_class:)
        end

        @tast.create_arena(binding, size, typed_body, span)
      end

      def infer_arena_new_call(arguments, env:, self_class:, span:)
        size = constant_capacity(keyword_value(arguments, :size), env:, self_class:)
        raise "Arena.new: the size must be known at compile time" if size.nil?

        @tast.create_arena_new(size, Arena.type(@tast), span)
      end

      def keyword_value(arguments, name)
        argument = arguments.find do |candidate|
          @bareruby_ast.node_type(candidate) == :keyword_argument &&
            @bareruby_ast.children_of(candidate)[0] == name
        end
        argument && @bareruby_ast.children_of(argument)[1]
      end

      # The length is a run-time value: reserving room for it is the whole reason the
      # arena exists. The element type is left open and the first assignment settles it,
      # as Array.new(n) does.
      def infer_arena_method_call(name, receiver_tast, arguments, env:, self_class:, span:)
        return infer_arena_reset_call(receiver_tast, span) if name == :reset
        if name == :string
          return infer_arena_string_call(receiver_tast, arguments.first, env:, self_class:, span:)
        end
        raise "an arena answers array, string and reset, not #{name}" unless name == :array

        length = infer_node(arguments[0], env:, self_class:)
        @tast.create_arena_alloc(receiver_tast, length, ArenaArray.type(@tast), span)
      end

      # The string a program can grow. Its handle lives in the region along with its bytes,
      # so every binding names the one string — appending through any of them is seen
      # through all of them, which is what Ruby does — and a method can hand one back.
      # The initial contents may be a static string, another variable-length string, or an
      # interpolation, which is the one form whose length is measured while running rather
      # than estimated while compiling.
      def infer_arena_string_call(receiver_tast, source, env:, self_class:, span:)
        if formatted?(source)
          arguments = format_arguments(receiver_tast, source, env:, self_class:, span:)
          return string_call(:string, ArenaString::FORMAT_FUNCTION, arguments, ArenaString.type(@tast), span)
        end

        initial = source ? text_of(source, env:, self_class:) : @tast.create_string("", :String, span)
        string_call(:string, ArenaString::NEW_FUNCTION, [receiver_tast, initial], ArenaString.type(@tast), span)
      end

      # Growing, joining and comparing all reach the runtime, which owns the representation:
      # nothing the backend emits knows what a string is made of.
      def infer_arena_string_method_call(name, receiver_tast, arguments, env:, self_class:, span:)
        return receiver_tast if name == :to_s
        return string_call(name, ArenaString::LENGTH_FUNCTION, [receiver_tast], :Int32, span) if SIZE_NAMES.include?(name)
        return string_call(name, ArenaString::DUP_FUNCTION, [receiver_tast], ArenaString.type(@tast), span) if name == :dup

        source = arguments.first
        if name == :<< && formatted?(source)
          appended = format_arguments(receiver_tast, source, env:, self_class:, span:)
          return string_call(name, ArenaString::APPEND_FORMAT_FUNCTION, appended, ArenaString.type(@tast), span)
        end

        infer_string_operator_call(name, receiver_tast, source, env:, self_class:, span:)
      end

      def infer_string_operator_call(name, receiver_tast, source, env:, self_class:, span:)
        function = ArenaString.operator_function(name)
        comparison = COMPARISON_OPERATORS.include?(name)
        arguments = [receiver_tast, text_of(source, env:, self_class:)]
        call = string_call(name, function, arguments, comparison ? :Bool : ArenaString.type(@tast), span)
        name == :!= ? negate(call, span) : call
      end

      def format_arguments(receiver_tast, source, env:, self_class:, span:)
        format, values = format_of(source, env:, self_class:)
        [receiver_tast, @tast.create_string(format, :String, span)] + values
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

      def text_of(node, env:, self_class:) = string_value_of(infer_node(node, env:, self_class:))

      # A variable-length string reaches everything that takes a static string — puts, a
      # UART, a format value, another string — through the bytes the region holds.
      def string_value_of(node)
        return node unless ArenaString.type?(@tast.value_type(node))

        string_call(:bytes, ArenaString::BYTES_FUNCTION, [node], :String, @tast.span_of(node))
      end

      def infer_arena_reset_call(receiver_tast, span)
        callee = @tast.create_callee(:binding_method, :Arena, :reset, Arena::RESET_FUNCTION, [], :Nil)
        @tast.create_call(receiver_tast, callee, [], nil, :Nil, span)
      end

      # size is a field rather than a folded constant, because an arena array is the one
      # array whose length the compiler does not know.
      def infer_arena_array_method_call(name, receiver_tast, receiver_type, arguments, env:, self_class:, span:)
        return @tast.create_arena_length(receiver_tast, :Int32, span) if SIZE_NAMES.include?(name)

        index = infer_node(arguments[0], env:, self_class:)
        return infer_index_assign(receiver_tast, receiver_type, index, arguments[1], env:, self_class:, span:) if name == :[]=

        element_type = receiver_type[:element]
        raise "the element type of this arena array is not known yet" if element_type.nil?

        @tast.create_index(receiver_tast, index, element_type, span)
      end

      # The simple check the design asks for while a full lifetime analysis is still out
      # of scope: neither an allocation nor the arena it came from may be stored where the
      # release cannot reach it. An instance variable outlives every block, and so does a
      # local the block did not introduce. Creating a long-lived arena there is the one
      # thing that is not an escape, because it is where that arena begins.
      def reject_arena_escape(kind, name, value_tast)
        type = @tast.value_type(value_tast)
        return unless ArenaArray.type?(type) || ArenaString.type?(type) ||
                      (Arena.type?(type) && @tast.node_type(value_tast) != :arena_new)
        return unless kind == :instance || @arena&.outlived_by?(name)

        raise "an arena and what it holds cannot be stored in #{name}, which outlives them"
      end

      def constant_receiver?(receiver)
        @bareruby_ast.node_type(receiver) == :reference &&
          @bareruby_ast.children_of(receiver)[0] == :constant
      end

      def infer_self_method_call(name, arguments, env:, self_class:, span:)
        argument_tasts = arguments.map { |argument| infer_node(argument, env:, self_class:) }
        resolved = resolve_method_call(find_method(self_class, name), argument_types(argument_tasts))
        callee = @tast.create_callee(
          :user_method, resolved.owner, name, function_name(resolved.owner, name),
          resolved.parameter_types, resolved.return_type
        )
        @tast.create_call(nil, callee, argument_tasts, nil, resolved.return_type, span)
      end

      def infer_instance_method_call(receiver_tast, receiver_type, name, arguments, env:, self_class:, span:)
        class_name = receiver_type[:class_name]
        if PERIPHERALS.key?(class_name)
          if class_name == :UART && %i[read gets].include?(name)
            return infer_uart_receive_call(
              receiver_tast, name, arguments, env:, self_class:, span:
            )
          end
          if class_name == :I2C && %i[read write].include?(name)
            return infer_i2c_call(receiver_tast, name, arguments, env:, self_class:, span:)
          end

          signature = PERIPHERALS.fetch(class_name)[:methods].fetch(name)
          printf_function = PRINTF_BINDINGS[signature[:function]]
          if printf_function && formatted?(arguments.first)
            return infer_printf_call(
              printf_function, receiver_tast, arguments.first, env:, self_class:, span:
            )
          end

          argument_tasts = arguments.map { |argument| infer_node(argument, env:, self_class:) }
          return infer_binding_method_call(receiver_tast, class_name, name, argument_tasts, span)
        end

        argument_tasts = arguments.map { |argument| infer_node(argument, env:, self_class:) }

        resolved = resolve_method_call(find_method(class_name, name), argument_types(argument_tasts))
        callee = @tast.create_callee(
          :user_method, resolved.owner, name, function_name(resolved.owner, name),
          resolved.parameter_types, resolved.return_type
        )
        @tast.create_call(receiver_tast, callee, argument_tasts, nil, resolved.return_type, span)
      end

      # A received string belongs to the innermost active region. The region is an
      # implementation argument only: the Ruby call keeps the standard UART read/gets
      # shape while the generated binding receives somewhere to put the bytes.
      def infer_uart_receive_call(receiver_tast, name, arguments, env:, self_class:, span:)
        signature = PERIPHERALS.fetch(:UART)[:methods].fetch(name)
        arena = current_arena(span)
        argument_tasts = [arena] + arguments.map { |argument| infer_node(argument, env:, self_class:) }
        callee = @tast.create_callee(
          :binding_method, :UART, name, signature[:function],
          argument_types(argument_tasts), ArenaString.type(@tast)
        )
        @tast.create_call(receiver_tast, callee, argument_tasts, nil, ArenaString.type(@tast), span)
      end

      # I2C uses the current region both for a read result and for the temporary byte
      # sequence that makes heterogeneous write arguments one bus transaction.
      def infer_i2c_call(receiver_tast, name, arguments, env:, self_class:, span:)
        signature = PERIPHERALS.fetch(:I2C)[:methods].fetch(name)
        argument_tasts = [current_arena(span)] +
                         arguments.map { |argument| infer_node(argument, env:, self_class:) }
        return_type = name == :read ? ArenaString.type(@tast) : :Int32
        callee = @tast.create_callee(
          :binding_i2c, :I2C, name, signature[:function],
          argument_types(argument_tasts), return_type
        )
        @tast.create_call(receiver_tast, callee, argument_tasts, nil, return_type, span)
      end

      def current_arena(span) = @tast.create_reference(@arena.binding, Arena.type(@tast), span)

      def inside_arena(arena)
        enclosing = @arena
        @arena = arena
        yield
      ensure
        @arena = enclosing
      end

      def infer_new_call(class_name, arguments, env:, self_class:, span:)
        argument_tasts = arguments.map { |argument| infer_node(argument, env:, self_class:) }
        types = argument_types(argument_tasts)
        resolve_method_call(find_method(class_name, :initialize), types)
        instance_type = @tast.create_instance_type(class_name)
        callee = @tast.create_callee(
          :new, class_name, :new, function_name(class_name, :initialize), types, instance_type
        )
        @tast.create_call(nil, callee, argument_tasts, nil, instance_type, span)
      end

      def infer_binding_new_call(class_name, arguments, env:, self_class:, span:)
        peripheral = PERIPHERALS.fetch(class_name)
        constructor = peripheral[:constructor]
        argument_tasts = resolve_keywords(arguments, constructor[:keywords] || {}, env:, self_class:, span:)
        verify_gpio_direction(argument_tasts) if class_name == :GPIO
        verify_adc_pin(argument_tasts) if class_name == :ADC
        instance_type = @tast.create_instance_type(class_name, peripheral[:struct])
        callee = @tast.create_callee(
          :binding_new, class_name, :new, constructor[:function],
          argument_types(argument_tasts), instance_type
        )
        @tast.create_call(nil, callee, argument_tasts, nil, instance_type, span)
      end

      # Exactly one of IN / OUT / HIGH_Z is mandatory. The standard guideline raises
      # ArgumentError at run time; one-hot constants let us fold the params expression and
      # reject it while compiling instead.
      def verify_gpio_direction(argument_tasts)
        params = constant_integer(argument_tasts[1])
        return if params.nil?

        directions = (params & GPIO_DIRECTION_MASK).digits(2).count(1)
        return if directions == 1

        raise "GPIO.new: params must name exactly one of GPIO::IN, GPIO::OUT and GPIO::HIGH_Z"
      end

      # Pins without a converter channel are rejected while compiling.
      def verify_adc_pin(argument_tasts)
        pin = constant_integer(argument_tasts[0])
        return if pin.nil? || ADC_CHANNEL_PINS.include?(pin)

        raise "ADC.new: pin #{pin} has no converter channel (expected #{ADC_CHANNEL_PINS})"
      end

      def constant_integer(node)
        return nil if node.nil?
        return @tast.children_of(node)[0] if @tast.node_type(node) == :integer
        return nil unless @tast.node_type(node) == :call

        receiver, callee, arguments = @tast.children_of(node)
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

        tasts = positional.map { |argument| infer_node(argument, env:, self_class:) }
        keywords.each do |name, default|
          value = supplied[name]
          tasts << (value ? infer_node(value, env:, self_class:) : @tast.create_integer(default, literal_type(default), span))
        end
        tasts
      end

      def infer_binding_method_call(receiver_tast, class_name, name, argument_tasts, span)
        signature = PERIPHERALS.fetch(class_name)[:methods].fetch(name)
        callee = @tast.create_callee(
          :binding_method, class_name, name, signature[:function],
          signature[:parameter_types], signature[:return_type]
        )
        arguments = argument_tasts.map { |argument| string_value_of(argument) }
        @tast.create_call(receiver_tast, callee, arguments, nil, signature[:return_type], span)
      end

      def infer_gpio_interrupt_call(receiver_tast, arguments, block, env:, self_class:, span:)
        events = resolve_keywords(arguments, { edge: 0 }, env:, self_class:, span:).first
        parameters, body = @bareruby_ast.children_of(block)
        typed_body = infer_body(body, env: {}, self_class:)
        typed_block = @tast.create_block(parameters, typed_body, :Nil, span_of(block))
        @tast.create_interrupt(receiver_tast, events, typed_block, :Nil, span)
      end

      def infer_module_function_call(module_name, name, arguments, env:, self_class:, span:)
        signature = PERIPHERAL_MODULES.fetch(module_name).fetch(name)
        argument_tasts = arguments.map { |argument| infer_node(argument, env:, self_class:) }
        callee = @tast.create_callee(
          :binding_function, module_name, name, signature[:function],
          signature[:parameter_types], signature[:return_type]
        )
        @tast.create_call(nil, callee, argument_tasts, nil, signature[:return_type], span)
      end

      def infer_binding_function_call(name, arguments, env:, self_class:, span:)
        signature = PERIPHERAL_FUNCTIONS.fetch(name)
        argument_tasts = arguments.map { |argument| infer_node(argument, env:, self_class:) }
        callee = @tast.create_callee(
          :binding_function, nil, name, signature[:function],
          signature[:parameter_types], signature[:return_type]
        )
        @tast.create_call(nil, callee, argument_tasts, nil, signature[:return_type], span)
      end

      # ? and ! are legal in Ruby method names but not in C identifiers.
      def function_name(owner, name)
        :"#{owner}_#{name.to_s.sub(/\?\z/, '_p').sub(/!\z/, '_bang').sub(/=\z/, '_set')}"
      end

      def fixed?(type) = type == :Fixed

      # A conversion whose source already has the target type is the identity.
      def infer_conversion_call(name, receiver_tast, receiver_type, span)
        conversion = CONVERSIONS.fetch(name)
        return receiver_tast if receiver_type == conversion[:return_type]
        return to_fixed(receiver_tast) if name == :to_fixed

        callee = @tast.create_callee(
          :builtin_function, nil, name, conversion[:function], [receiver_type], conversion[:return_type]
        )
        @tast.create_call(nil, callee, [receiver_tast], nil, conversion[:return_type], span)
      end

      # The builtin signature table for Fixed: an integer
      # operand is converted with to_fixed semantics, add and subtract act directly on
      # the Q16.16 representation, and multiply and divide go through the runtime so the
      # doubled intermediate, the rounding and the saturation all happen there.
      def infer_fixed_operator_call(name, receiver_tast, argument_tasts, span)
        receiver = to_fixed(receiver_tast)
        arguments = argument_tasts.map { |argument| to_fixed(argument) }

        return infer_fixed_runtime_call(name, receiver, arguments, span) if %i[* /].include?(name)

        result_type = COMPARISON_OPERATORS.include?(name) ? :Bool : :Fixed
        callee = @tast.create_callee(:builtin_operator, nil, name, nil, argument_types(arguments), result_type)
        @tast.create_call(receiver, callee, arguments, nil, result_type, span)
      end

      def infer_fixed_runtime_call(name, receiver, arguments, span)
        function = name == :* ? :bareruby_fixed_mul : :bareruby_fixed_div
        callee = @tast.create_callee(:builtin_function, nil, name, function, %i[Fixed Fixed], :Fixed)
        @tast.create_call(nil, callee, [receiver] + arguments, nil, :Fixed, span)
      end

      def to_fixed(node)
        return node if fixed?(@tast.value_type(node))

        if @tast.node_type(node) == :integer
          return @tast.create_integer(@tast.children_of(node)[0] * FIXED_ONE, :Fixed, @tast.span_of(node))
        end

        callee = @tast.create_callee(
          :builtin_function, nil, :to_fixed, :bareruby_int32_to_fixed, %i[Int32], :Fixed
        )
        @tast.create_call(nil, callee, [node], nil, :Fixed, @tast.span_of(node))
      end

      def operator?(name)
        UNARY_OPERATORS.include?(name) || BINARY_OPERATORS.include?(name) ||
          COMPARISON_OPERATORS.include?(name) || name == :!
      end

      def infer_operator_call(name, receiver_tast, receiver_type, arguments, env:, self_class:, span:)
        argument_tasts = arguments.map { |argument| infer_node(argument, env:, self_class:) }
        if fixed?(receiver_type) || argument_tasts.any? { |a| fixed?(@tast.value_type(a)) }
          return infer_fixed_operator_call(name, receiver_tast, argument_tasts, span)
        end

        result_type =
          if COMPARISON_OPERATORS.include?(name) || name == :!
            :Bool
          elsif UNARY_OPERATORS.include?(name)
            receiver_type
          else
            widen(receiver_type, @tast.value_type(argument_tasts.first))
          end
        callee = @tast.create_callee(:builtin_operator, nil, name, nil, argument_types(argument_tasts), result_type)
        @tast.create_call(receiver_tast, callee, argument_tasts, nil, result_type, span)
      end

      def infer_iterator_call(name, receiver_tast, receiver_type, arguments, block, env:, self_class:, span:)
        argument_tasts = arguments.map { |argument| infer_node(argument, env:, self_class:) }
        element_type = name == :upto ? widen(receiver_type, @tast.value_type(argument_tasts.first)) : receiver_type
        block_tast = block && infer_iterator_block(block, element_type, env:, self_class:)
        callee = @tast.create_callee(:builtin_iterator, nil, name, nil, argument_types(argument_tasts), :Nil)
        @tast.create_call(receiver_tast, callee, argument_tasts, block_tast, :Nil, span)
      end

      def infer_loop_call(block, env:, self_class:, span:)
        block_tast = block && infer_iterator_block(block, nil, env:, self_class:)
        callee = @tast.create_callee(:builtin_iterator, nil, :loop, nil, [], :Nil)
        @tast.create_call(nil, callee, [], block_tast, :Nil, span)
      end

      # puts is expanded at compile time: an interpolation becomes a format string plus
      # its values, with no intermediate buffer.
      def infer_puts_call(arguments, env:, self_class:, span:)
        argument = arguments.first
        return infer_printf_call(:bareruby_printf, nil, argument, env:, self_class:, span:) if formatted?(argument)

        argument_tasts = arguments.map { |a| text_of(a, env:, self_class:) }
        callee = @tast.create_callee(
          :builtin_puts, nil, :puts, puts_function(argument_tasts), argument_types(argument_tasts), :Nil
        )
        @tast.create_call(nil, callee, argument_tasts, nil, :Nil, span)
      end

      def formatted?(node)
        return false if node.nil?

        @bareruby_ast.node_type(node) == :interpolation
      end

      def infer_printf_call(function, receiver_tast, node, env:, self_class:, span:)
        format, values = format_of(node, env:, self_class:)
        arguments = [@tast.create_string("#{format}\n", :String, span_of(node))] + values
        kind = receiver_tast ? :binding_printf : :builtin_printf
        callee = @tast.create_callee(kind, nil, :printf, function, argument_types(arguments), :Nil)
        @tast.create_call(receiver_tast, callee, arguments, nil, :Nil, span)
      end

      # Widest rendering of each type, used to size the temporary buffer an interpolation
      # assigns into. A String of unknown capacity has no honest bound here; a real
      # implementation would carry the capacity in the type, so this is the one number in
      # the estimate that is a placeholder rather than a derivation.
      MAX_LENGTHS = { Int32: 11, Int64: 20, Bool: 5, Fixed: 12, String: 64 }.freeze

      # An interpolation outside a puts argument becomes a fixed-capacity buffer plus a
      # compile-time bound on what can land in it. An arena string is the way out of that
      # estimate: a.string("...") measures the rendering while running instead.
      def infer_format(node, env:, self_class:)
        format, values, parts = format_of(node, env:, self_class:)
        capacity = parts.sum { |part| part_length(part) } + 1

        @tast.create_format(
          capacity, @tast.create_string(format, :String, span_of(node)), values, :String, span_of(node)
        )
      end

      def part_length(part)
        return @tast.children_of(part)[0].bytesize if @tast.node_type(part) == :string

        MAX_LENGTHS.fetch(@tast.value_type(part), 32)
      end

      # One interpolation, read once: the static parts become the format and the rest
      # become its values, whichever of the four forms is asking.
      def format_of(node, env:, self_class:)
        parts = @bareruby_ast.children_of(node)[0].map { |part| infer_node(part, env:, self_class:) }
        format = +""
        values = []

        parts.each do |part|
          if @tast.node_type(part) == :string
            format << escape_format(@tast.children_of(part)[0])
          else
            format << conversion_of(@tast.value_type(part))
            values << to_s_of(part)
          end
        end

        [format, values, parts]
      end

      def escape_format(text) = text.gsub("%", "%%")

      def conversion_of(type)
        return "%s" if ArenaString.type?(type)

        case type
        when :Int64 then "%lld"
        when :String, :Bool, :Fixed then "%s"
        else "%d"
        end
      end

      # Bool and Fixed have no printf conversion of their own, so to_s is a real call.
      TO_S_FUNCTIONS = { Bool: :bareruby_bool_to_s, Fixed: :bareruby_fixed_to_s }.freeze

      def to_s_of(part)
        return string_value_of(part) if ArenaString.type?(@tast.value_type(part))

        function = TO_S_FUNCTIONS[@tast.value_type(part)]
        return part unless function

        callee = @tast.create_callee(
          :builtin_function, nil, :to_s, function, [@tast.value_type(part)], :String
        )
        @tast.create_call(nil, callee, [part], nil, :String, @tast.span_of(part))
      end

      def infer_iterator_block(block_node, element_type, env:, self_class:)
        parameters, body = @bareruby_ast.children_of(block_node)
        block_env = env.dup
        bindings = parameters.map do |parameter|
          @tast.create_binding(:local, @bareruby_ast.children_of(parameter)[0])
        end
        bindings.each { |binding| block_env[binding[:name]] = [binding, element_type] }
        typed_body = infer_body(body, env: block_env, self_class:)
        typed_parameters = bindings.zip(parameters).map do |binding, parameter|
          @tast.create_parameter(binding, element_type, span_of(parameter))
        end
        @tast.create_block(typed_parameters, typed_body, :Nil, span_of(block_node))
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
        return unify_array_types(left, right) if same_array_shape?(left, right)
        return left if left == right
        return right if left == :Nil && nilable_type?(right)
        return left if right == :Nil && nilable_type?(left)
        return @tast.create_nilable_type(right) if left == :Nil
        return @tast.create_nilable_type(left) if right == :Nil
        if nilable_type?(left) || nilable_type?(right)
          left_inner = nilable_type?(left) ? left[:inner] : left
          right_inner = nilable_type?(right) ? right[:inner] : right
          return @tast.create_nilable_type(unify(left_inner, right_inner))
        end

        widen(left, right)
      end

      # A missing element type means inference has not reached the first write yet; it is
      # not Nil. Propagate the known element type into both views of the same-shaped array.
      # Returning the newer view keeps later first-write inference connected to the
      # binding when both sides are still open here.
      def unify_array_types(left, right)
        element =
          if left[:element].nil?
            right[:element]
          elsif right[:element].nil?
            left[:element]
          else
            unify(left[:element], right[:element])
          end
        left[:element] = element
        right[:element] = element
        right
      end

      def same_array_shape?(left, right)
        return false unless left.is_a?(Hash) && right.is_a?(Hash)
        return true if left[:kind] == :arena_array && right[:kind] == :arena_array

        left[:kind] == :array && right[:kind] == :array && left[:capacity] == right[:capacity]
      end

      def nilable_type?(type) = type.is_a?(Hash) && type[:kind] == :nilable

      def span_of(node) = @bareruby_ast.span_of(node)
    end
  end
end
