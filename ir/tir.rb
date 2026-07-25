# frozen_string_literal: true

module BareRubyProt
  class TIR
    SCHEMA = "TIR"

    def self.restore(payload)
      tir = allocate
      tir.install(payload)
      tir
    end

    def initialize
      @tree = build(:program, [[]], nil)
    end

    def install(payload)
      @tree = payload[:tree]
    end

    def dump_payload
      { tree: @tree }
    end

    def create_binding(kind, name) = { kind:, name: }

    def create_instance_type(class_name, struct = nil) = { kind: :instance, class_name:, struct: }

    def create_identity(owner, name, parameter_types, return_type)
      { owner:, name:, parameter_types:, return_type: }
    end

    def create_callee(kind, owner, name, function, parameter_types, return_type)
      { kind:, owner:, name:, function:, parameter_types:, return_type: }
    end

    def create_integer(value, type, span) = build(:integer, [value, type], span)

    def create_reference(binding, type, span) = build(:reference, [binding, type], span)

    def create_assignment(binding, value, type, span) = build(:assignment, [binding, value, type], span)

    def create_parameter(binding, type, span) = build(:parameter, [binding, type], span)

    def create_method_definition(identity, parameters, body, span)
      build(:method_definition, [identity, parameters, body], span)
    end

    def create_class_definition(name, ivars, methods, span)
      build(:class_definition, [name, ivars, methods], span)
    end

    def create_call(receiver, callee, arguments, block, type, span)
      build(:call, [receiver, callee, arguments, block, type], span)
    end

    def create_block(parameters, body, type, span) = build(:block, [parameters, body, type], span)

    def create_return(value, type, span) = build(:return, [value, type], span)

    def create_iteration_control(kind, span) = build(:iteration_control, [kind], span)

    def create_for_range(binding, type, start_value, limit_value, inclusive, body, span)
      build(:for_range, [binding, type, start_value, limit_value, inclusive, body], span)
    end

    def create_while_true(body, span) = build(:while_true, [body], span)

    def create_boolean(value, type, span) = build(:boolean, [value, type], span)

    def create_string(value, type, span) = build(:string, [value, type], span)

    def create_symbol(name, type, span) = build(:symbol, [name, type], span)

    def create_if(condition, then_body, else_body, type, span)
      build(:if, [condition, then_body, else_body, type], span)
    end

    def create_while(condition, body, span) = build(:while, [condition, body], span)

    def create_logical(operator, left, right, type, span)
      build(:logical, [operator, left, right, type], span)
    end

    def replace_program(body)
      @tree = build(:program, [body], nil)
      self
    end

    def program_body = @tree[:children][0]

    def node_type(node) = node[:type]

    def children_of(node) = node[:children]

    def span_of(node) = node[:span]

    def value_type(node) = node[:children].last

    def inspect_text
      program_body.flat_map { |statement| inspect_lines(statement, "") }.join("\n")
    end

    def inspect_lines(node, indent)
      case node[:type]
      when :class_definition
        name, ivars, methods = node[:children]
        ivar_text = ivars.map { |ivar| "#{ivar[:name]}: #{inspect_type(ivar[:type])}" }.join(", ")
        [gutter(node) + "#{indent}class_definition(#{name.inspect}, ivars[#{ivar_text}])"] +
          methods.flat_map { |method| inspect_lines(method, "#{indent}  ") }
      when :method_definition
        identity, parameters, body = node[:children]
        parameter_text = parameters.map { |parameter| inspect_inline(parameter) }.join(", ")
        header = "method_definition(#{identity[:owner].inspect}##{identity[:name]}, " \
                 "[#{parameter_text}]) -> #{inspect_type(identity[:return_type])}"
        [gutter(node) + "#{indent}#{header}"] +
          body.flat_map { |statement| inspect_lines(statement, "#{indent}  ") }
      when :call
        block = node[:children][3]
        header = [gutter(node) + "#{indent}#{inspect_inline(node)}"]
        block ? header + block[:children][1].flat_map { |statement| inspect_lines(statement, "#{indent}  ") } : header
      when :assignment
        binding, value, type = node[:children]
        if value[:type] == :call && value[:children][3]
          header = "assignment(#{binding[:kind]} #{binding[:name]}, #{inspect_inline(value)}, #{inspect_type(type)})"
          [gutter(node) + "#{indent}#{header}"] +
            value[:children][3][:children][1].flat_map { |statement| inspect_lines(statement, "#{indent}  ") }
        else
          [gutter(node) + "#{indent}#{inspect_inline(node)}"]
        end
      when :for_range
        binding, type, start_value, limit_value, inclusive, body = node[:children]
        header = "for_range(#{binding[:name]}: #{inspect_type(type)}, #{inspect_inline(start_value)}, " \
                 "#{inspect_inline(limit_value)}, #{inclusive ? 'inclusive' : 'exclusive'})"
        [gutter(node) + "#{indent}#{header}"] +
          body.flat_map { |statement| inspect_lines(statement, "#{indent}  ") }
      when :while_true
        [gutter(node) + "#{indent}while_true"] +
          node[:children][0].flat_map { |statement| inspect_lines(statement, "#{indent}  ") }
      when :if
        condition, then_body, else_body, type = node[:children]
        lines = [gutter(node) + "#{indent}if(#{inspect_inline(condition)}) -> #{inspect_type(type)}"]
        lines += then_body.flat_map { |statement| inspect_lines(statement, "#{indent}  ") }
        if else_body
          lines << "#{gutter(node)}#{indent}else"
          lines += else_body.flat_map { |statement| inspect_lines(statement, "#{indent}  ") }
        end
        lines
      when :while
        condition, body = node[:children]
        [gutter(node) + "#{indent}while(#{inspect_inline(condition)})"] +
          body.flat_map { |statement| inspect_lines(statement, "#{indent}  ") }
      else
        [gutter(node) + "#{indent}#{inspect_inline(node)}"]
      end
    end

    def inspect_inline(node)
      case node[:type]
      when :integer
        value, type = node[:children]
        "integer(#{value.inspect}, #{inspect_type(type)})"
      when :reference
        binding, type = node[:children]
        "reference(#{binding[:kind]} #{binding[:name]}, #{inspect_type(type)})"
      when :parameter
        binding, type = node[:children]
        "parameter(#{binding[:name]}, #{inspect_type(type)})"
      when :assignment
        binding, value, type = node[:children]
        "assignment(#{binding[:kind]} #{binding[:name]}, #{inspect_inline(value)}, #{inspect_type(type)})"
      when :return
        value, type = node[:children]
        "return(#{value ? inspect_inline(value) : 'nil'}, #{inspect_type(type)})"
      when :iteration_control
        "iteration_control(#{node[:children][0].inspect})"
      when :boolean
        value, type = node[:children]
        "boolean(#{value.inspect}, #{inspect_type(type)})"
      when :string
        value, type = node[:children]
        "string(#{value.inspect}, #{inspect_type(type)})"
      when :symbol
        name, type = node[:children]
        "symbol(#{name.inspect}, #{inspect_type(type)})"
      when :logical
        operator, left, right, type = node[:children]
        "logical(#{operator}, #{inspect_inline(left)}, #{inspect_inline(right)}, #{inspect_type(type)})"
      when :if
        condition, _then_body, _else_body, type = node[:children]
        "if(#{inspect_inline(condition)}) -> #{inspect_type(type)}"
      when :call
        receiver, callee, arguments, block, type = node[:children]
        parts = [receiver ? inspect_inline(receiver) : "nil", "#{callee[:kind]}:#{callee[:name]}"]
        parts << "[#{arguments.map { |argument| inspect_inline(argument) }.join(', ')}]"
        if block
          parameters = block[:children][0]
          parts << "block(#{parameters.map { |parameter| inspect_inline(parameter) }.join(', ')})"
        end
        parts << inspect_type(type)
        "call(#{parts.join(', ')})"
      end
    end

    def inspect_type(type)
      type.is_a?(Hash) ? "instance(#{type[:class_name]})" : type.to_s
    end

    def gutter(node)
      node[:span] ? format("%3d| ", node[:span][:start][:line]) : "   | "
    end

    private

    def build(type, children, span) = { type:, children:, span: }
  end
end
