# frozen_string_literal: true

require_relative "../ir/tir"

module BareRubyProt
  module Pass
    class TypeInferrer
      RECEIVER_ITERATOR_NAMES = %i[times upto].freeze
      UNARY_OPERATORS = %i[-@ ~].freeze
      BINARY_OPERATORS = %i[+ - * / % << >> & | ^].freeze
      INTEGER_WIDTHS = %i[Int8 Int16 Int32 Int64].freeze
      INTEGER_RANGES = {
        Int8: (-128..127),
        Int16: (-32_768..32_767),
        Int32: (-(2**31)..(2**31 - 1)),
        Int64: (-(2**63)..(2**63 - 1))
      }.freeze

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
          if method_info.name == :initialize
            :Nil
          else
            typed_body.empty? ? :Nil : @tir.value_type(typed_body.last)
          end
      end

      def infer_body(statements, env:, self_class:)
        statements.map { |statement| infer_node(statement, env:, self_class:) }
      end

      def infer_node(node, env:, self_class:)
        case @bareruby_ast.node_type(node)
        when :integer then infer_integer(node)
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
          else infer_self_method_call(name, arguments, env:, self_class:, span:)
          end
        elsif constant_receiver?(receiver) && name == :new
          infer_new_call(@bareruby_ast.children_of(receiver)[1], arguments, env:, self_class:, span:)
        else
          receiver_tir = infer_node(receiver, env:, self_class:)
          receiver_type = @tir.value_type(receiver_tir)

          if UNARY_OPERATORS.include?(name) || BINARY_OPERATORS.include?(name)
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
        callee = @tir.create_callee(:user_method, resolved.owner, name, resolved.parameter_types, resolved.return_type)
        @tir.create_call(nil, callee, argument_tirs, nil, resolved.return_type, span)
      end

      def infer_instance_method_call(receiver_tir, receiver_type, name, arguments, env:, self_class:, span:)
        argument_tirs = arguments.map { |argument| infer_node(argument, env:, self_class:) }
        resolved = resolve_method_call(find_method(receiver_type[:class_name], name), argument_types(argument_tirs))
        callee = @tir.create_callee(:user_method, resolved.owner, name, resolved.parameter_types, resolved.return_type)
        @tir.create_call(receiver_tir, callee, argument_tirs, nil, resolved.return_type, span)
      end

      def infer_new_call(class_name, arguments, env:, self_class:, span:)
        argument_tirs = arguments.map { |argument| infer_node(argument, env:, self_class:) }
        types = argument_types(argument_tirs)
        resolve_method_call(find_method(class_name, :initialize), types)
        instance_type = @tir.create_instance_type(class_name)
        callee = @tir.create_callee(:new, class_name, :new, types, instance_type)
        @tir.create_call(nil, callee, argument_tirs, nil, instance_type, span)
      end

      def infer_operator_call(name, receiver_tir, receiver_type, arguments, env:, self_class:, span:)
        argument_tirs = arguments.map { |argument| infer_node(argument, env:, self_class:) }
        result_type =
          if UNARY_OPERATORS.include?(name)
            receiver_type
          else
            widen(receiver_type, @tir.value_type(argument_tirs.first))
          end
        callee = @tir.create_callee(:builtin_operator, nil, name, argument_types(argument_tirs), result_type)
        @tir.create_call(receiver_tir, callee, argument_tirs, nil, result_type, span)
      end

      def infer_iterator_call(name, receiver_tir, receiver_type, arguments, block, env:, self_class:, span:)
        argument_tirs = arguments.map { |argument| infer_node(argument, env:, self_class:) }
        element_type = name == :upto ? widen(receiver_type, @tir.value_type(argument_tirs.first)) : receiver_type
        block_tir = block && infer_iterator_block(block, element_type, env:, self_class:)
        callee = @tir.create_callee(:builtin_iterator, nil, name, argument_types(argument_tirs), :Nil)
        @tir.create_call(receiver_tir, callee, argument_tirs, block_tir, :Nil, span)
      end

      def infer_loop_call(block, env:, self_class:, span:)
        block_tir = block && infer_iterator_block(block, nil, env:, self_class:)
        callee = @tir.create_callee(:builtin_iterator, nil, :loop, [], :Nil)
        @tir.create_call(nil, callee, [], block_tir, :Nil, span)
      end

      def infer_puts_call(arguments, env:, self_class:, span:)
        argument_tirs = arguments.map { |argument| infer_node(argument, env:, self_class:) }
        callee = @tir.create_callee(:builtin_puts, nil, :puts, argument_types(argument_tirs), :Nil)
        @tir.create_call(nil, callee, argument_tirs, nil, :Nil, span)
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

      def literal_type(value)
        width = INTEGER_WIDTHS.find { |candidate| INTEGER_RANGES.fetch(candidate).cover?(value) }
        widen(width, :Int32)
      end

      def widen(left, right)
        INTEGER_WIDTHS[[INTEGER_WIDTHS.index(left), INTEGER_WIDTHS.index(right)].max]
      end

      def span_of(node) = @bareruby_ast.span_of(node)
    end
  end
end
