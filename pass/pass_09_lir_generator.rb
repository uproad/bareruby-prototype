# frozen_string_literal: true

require_relative "../ir/lir"

module BareRubyProt
  module Pass
    class LirGenerator
      OPERATOR_TEXT = {
        :+ => "+", :- => "-", :* => "*", :/ => "/", :% => "%",
        :<< => "<<", :>> => ">>", :& => "&", :| => "|", :^ => "^",
        :-@ => "-", :~ => "~"
      }.freeze

      attr_reader :result

      def initialize(typed_ir)
        @tir = typed_ir
        @lir = LIR.new
      end

      def run
        structs = []
        functions = []

        @tir.program_body.each do |statement|
          next unless class_definition?(statement)

          name, ivars, methods = @tir.children_of(statement)
          structs << @lir.create_struct(name, ivars.map { |ivar| @lir.create_field(field_name(ivar[:name]), lir_type(ivar[:type])) })
          methods.each { |method| functions << lower_method(method) }
        end

        functions << lower_main
        @result = @lir.replace_module(structs, functions)

        self
      end

      def class_definition?(node) = @tir.node_type(node) == :class_definition

      def lower_method(node)
        identity, parameters, body = @tir.children_of(node)
        begin_function(identity[:owner], identity[:return_type])

        lir_parameters = [{ name: :self, type: @self_type }]
        parameters.each do |parameter|
          binding, type = @tir.children_of(parameter)
          @declared << binding[:name]
          lir_parameters << { name: binding[:name], type: lir_type(type) }
        end

        statements = body.flat_map { |statement| lower_statement(statement) }
        @lir.create_function(
          function_name(identity[:owner], identity[:name]),
          lir_parameters,
          lir_type(identity[:return_type]),
          statements
        )
      end

      def lower_main
        begin_function(nil, :Nil)
        statements = @tir.program_body.reject { |node| class_definition?(node) }
                         .flat_map { |node| lower_statement(node) }
        @lir.create_function(:bareruby_main, [], :void, statements)
      end

      def begin_function(self_class, return_type)
        @declared = []
        @temp_index = 0
        @self_type = self_class && @lir.pointer_type(@lir.struct_type(self_class))
        @void_return = lir_type(return_type) == :void
      end

      def lower_statement(node)
        case @tir.node_type(node)
        when :return then lower_return(node)
        when :for_range then lower_for_range(node)
        when :while_true then lower_while_true(node)
        when :iteration_control then lower_iteration_control(node)
        else
          statements, value = lower_expression(node)
          value && value[:type] == :call ? statements + [@lir.create_expression(value)] : statements
        end
      end

      def lower_return(node)
        value = @tir.children_of(node)[0]
        return [@lir.create_return(nil)] if value.nil?

        statements, expression = lower_expression(value)
        statements + [@lir.create_return(@void_return ? nil : expression)]
      end

      def lower_for_range(node)
        binding, type, start_value, limit_value, inclusive, body = @tir.children_of(node)
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
        [@lir.create_while(@lir.create_const_bool(true), lower_body(@tir.children_of(node)[0]))]
      end

      def lower_iteration_control(node)
        [@tir.children_of(node)[0] == :break ? @lir.create_break : @lir.create_next]
      end

      def lower_body(statements) = statements.flat_map { |statement| lower_statement(statement) }

      def lower_expression(node)
        case @tir.node_type(node)
        when :integer
          value, type = @tir.children_of(node)
          [[], @lir.create_const_int(value, lir_type(type))]
        when :reference
          binding, type = @tir.children_of(node)
          [[], place_of(binding, lir_type(type))]
        when :assignment
          lower_assignment(node)
        when :call
          lower_call(node)
        end
      end

      def lower_assignment(node)
        binding, value, type = @tir.children_of(node)
        statements, value_expression = lower_expression(value)
        place = place_of(binding, lir_type(type))

        if binding[:kind] == :local && !@declared.include?(binding[:name])
          @declared << binding[:name]
          [statements + [@lir.create_declare(binding[:name], lir_type(type), value_expression)], place]
        else
          [statements + [@lir.create_assign(place, value_expression)], place]
        end
      end

      def lower_call(node)
        receiver, callee, arguments, _block, type = @tir.children_of(node)
        case callee[:kind]
        when :builtin_operator then lower_operator(receiver, callee, arguments, type)
        when :builtin_puts then lower_puts(arguments)
        when :new then lower_new(callee, arguments)
        when :user_method then lower_user_method(receiver, callee, arguments)
        end
      end

      def lower_operator(receiver, callee, arguments, type)
        receiver_statements, receiver_expression = lower_expression(receiver)
        operator = OPERATOR_TEXT.fetch(callee[:name])
        return [receiver_statements, @lir.create_unary(operator, receiver_expression, lir_type(type))] if arguments.empty?

        argument_statements, argument_expressions = lower_arguments(arguments)
        [receiver_statements + argument_statements,
         @lir.create_binary(operator, receiver_expression, argument_expressions.first, lir_type(type))]
      end

      def lower_puts(arguments)
        statements, expressions = lower_arguments(arguments)
        name = @lir.value_type(expressions.first) == :int64 ? :bareruby_puts_int64 : :bareruby_puts_int32
        [statements, @lir.create_call(name, expressions, :void)]
      end

      def lower_new(callee, arguments)
        class_name = callee[:owner]
        struct = @lir.struct_type(class_name)
        instance_name = next_temp
        argument_statements, argument_expressions = lower_arguments(arguments)
        initializer = @lir.create_call(
          function_name(class_name, :initialize),
          [@lir.create_address_of(@lir.create_local(instance_name, struct))] + argument_expressions,
          :void
        )

        statements = [@lir.create_declare(instance_name, struct, nil)] + argument_statements +
                     [@lir.create_expression(initializer)]
        [statements, @lir.create_local(instance_name, struct)]
      end

      def lower_user_method(receiver, callee, arguments)
        receiver_statements, receiver_expression = receiver ? lower_expression(receiver) : [[], nil]
        self_argument = receiver_expression ? @lir.create_address_of(receiver_expression) : @lir.create_self_pointer(@self_type)
        argument_statements, argument_expressions = lower_arguments(arguments)

        [receiver_statements + argument_statements,
         @lir.create_call(
           function_name(callee[:owner], callee[:name]),
           [self_argument] + argument_expressions,
           lir_type(callee[:return_type])
         )]
      end

      def lower_arguments(arguments)
        statements = []
        expressions = arguments.map do |argument|
          argument_statements, expression = lower_expression(argument)
          statements.concat(argument_statements)
          expression
        end
        [statements, expressions]
      end

      def place_of(binding, type)
        if binding[:kind] == :local
          @lir.create_local(binding[:name], type)
        else
          @lir.create_field_access(@lir.create_self_pointer(@self_type), field_name(binding[:name]), type)
        end
      end

      def lir_type(type)
        case type
        when :Int8, :Int16, :Int32 then :int32
        when :Int64 then :int64
        when Hash then @lir.struct_type(type[:class_name])
        else :void
        end
      end

      def field_name(name) = name.to_s.delete_prefix("@").to_sym

      def function_name(owner, name) = :"#{owner}_#{name}"

      def next_temp
        @temp_index += 1
        :"temporary_#{@temp_index}"
      end
    end
  end
end
