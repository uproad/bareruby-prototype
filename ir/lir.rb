# frozen_string_literal: true

module BareRubyProt
  class LIR
    SCHEMA = "LIR"

    def self.restore(payload)
      lir = allocate
      lir.install(payload)
      lir
    end

    def initialize
      @tree = build(:module, [[], []])
    end

    def install(payload)
      @tree = payload[:tree]
    end

    def dump_payload
      { tree: @tree }
    end

    def pointer_type(target) = { kind: :pointer, target: }

    def struct_type(name) = { kind: :struct, name: }

    def create_field(name, type) = { name:, type: }

    def create_struct(name, fields) = build(:struct, [name, fields])

    def create_function(name, parameters, return_type, body)
      build(:function, [name, parameters, return_type, body])
    end

    def create_declare(name, type, value) = build(:declare, [name, type, value])

    def create_declare_buffer(name, capacity) = build(:declare_buffer, [name, capacity])

    def create_assign(place, value) = build(:assign, [place, value])

    def create_expression(value) = build(:expression, [value])

    def create_return(value) = build(:return, [value])

    def create_for(init, condition, step, body) = build(:for, [init, condition, step, body])

    def create_while(condition, body) = build(:while, [condition, body])

    def create_if(condition, then_body, else_body) = build(:if, [condition, then_body, else_body])

    def create_try(body, rescue_body) = build(:try, [body, rescue_body])

    def create_break = build(:break, [])

    def create_next = build(:next, [])

    def create_const_int(value, type) = build(:const_int, [value, type])

    def create_const_bool(value) = build(:const_bool, [value])

    def create_const_string(value) = build(:const_string, [value, :string_ptr])

    def create_local(name, type) = build(:local, [name, type])

    def create_self_pointer(type) = build(:self_pointer, [type])

    def create_field_access(base, name, type) = build(:field_access, [base, name, type])

    def create_address_of(value) = build(:address_of, [value])

    def create_binary(operator, left, right, type) = build(:binary, [operator, left, right, type])

    def create_unary(operator, operand, type) = build(:unary, [operator, operand, type])

    def create_call(name, arguments, type) = build(:call, [name, arguments, type])

    def replace_module(structs, functions)
      @tree = build(:module, [structs, functions])
      self
    end

    def structs = @tree[:children][0]

    def functions = @tree[:children][1]

    def node_type(node) = node[:type]

    def children_of(node) = node[:children]

    def value_type(node) = node[:children].last

    def inspect_text
      lines = structs.flat_map { |struct| inspect_struct(struct) }
      lines += functions.flat_map { |function| inspect_function(function) }
      lines.join("\n")
    end

    def inspect_struct(struct)
      name, fields = struct[:children]
      ["struct #{name}"] + fields.map { |field| "    #{field[:name]}: #{type_text(field[:type])}" } + [""]
    end

    def inspect_function(function)
      name, parameters, return_type, body = function[:children]
      parameter_text = parameters.map { |parameter| "#{parameter[:name]}: #{type_text(parameter[:type])}" }.join(", ")
      ["function #{name}(#{parameter_text}) -> #{type_text(return_type)}"] +
        body.flat_map { |statement| inspect_statement(statement, "    ") } + [""]
    end

    def inspect_statement(statement, indent)
      case statement[:type]
      when :declare
        name, type, value = statement[:children]
        ["#{indent}declare #{name}: #{type_text(type)}#{value ? " = #{expression_text(value)}" : ''}"]
      when :declare_buffer
        name, capacity = statement[:children]
        ["#{indent}declare_buffer #{name}[#{capacity}]"]
      when :assign
        place, value = statement[:children]
        ["#{indent}assign #{expression_text(place)} = #{expression_text(value)}"]
      when :expression
        ["#{indent}#{expression_text(statement[:children][0])}"]
      when :return
        value = statement[:children][0]
        ["#{indent}return #{value ? expression_text(value) : ''}".rstrip]
      when :for
        init, condition, step, body = statement[:children]
        header = "#{indent}for (#{inspect_statement(init, '').first.strip}; " \
                 "#{expression_text(condition)}; #{inspect_statement(step, '').first.strip})"
        [header] + body.flat_map { |child| inspect_statement(child, "#{indent}    ") }
      when :while
        condition, body = statement[:children]
        ["#{indent}while (#{expression_text(condition)})"] +
          body.flat_map { |child| inspect_statement(child, "#{indent}    ") }
      when :if
        condition, then_body, else_body = statement[:children]
        lines = ["#{indent}if (#{expression_text(condition)})"] +
                then_body.flat_map { |child| inspect_statement(child, "#{indent}    ") }
        if else_body
          lines << "#{indent}else"
          lines += else_body.flat_map { |child| inspect_statement(child, "#{indent}    ") }
        end
        lines
      when :try
        body, rescue_body = statement[:children]
        ["#{indent}try"] + body.flat_map { |child| inspect_statement(child, "#{indent}    ") } +
          ["#{indent}catch"] + rescue_body.flat_map { |child| inspect_statement(child, "#{indent}    ") }
      when :break
        ["#{indent}break"]
      when :next
        ["#{indent}next"]
      end
    end

    def expression_text(node)
      case node[:type]
      when :const_int then node[:children][0].to_s
      when :const_bool then node[:children][0].to_s
      when :const_string then node[:children][0].inspect
      when :local then node[:children][0].to_s
      when :self_pointer then "self"
      when :field_access
        base, name, = node[:children]
        "#{expression_text(base)}.#{name}"
      when :address_of then "&#{expression_text(node[:children][0])}"
      when :binary
        operator, left, right, = node[:children]
        "(#{expression_text(left)} #{operator} #{expression_text(right)})"
      when :unary
        operator, operand, = node[:children]
        "(#{operator}#{expression_text(operand)})"
      when :call
        name, arguments, = node[:children]
        "#{name}(#{arguments.map { |argument| expression_text(argument) }.join(', ')})"
      end
    end

    def type_text(type)
      case type
      when Hash
        type[:kind] == :pointer ? "#{type_text(type[:target])}*" : "struct #{type[:name]}"
      else
        type.to_s
      end
    end

    private

    def build(type, children) = { type:, children: }
  end
end
