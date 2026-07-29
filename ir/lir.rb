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

    def c_array_type(element, capacity) = { kind: :c_array, element:, capacity: }

    def create_field(name, type) = { name:, type: }

    def create_struct(name, fields) = build(:struct, [name, fields])

    def create_function(name, parameters, return_type, body, context: :normal)
      build(:function, [name, parameters, return_type, body, context])
    end

    def create_declare(name, type, value) = build(:declare, [name, type, value])

    def create_declare_buffer(name, capacity) = build(:declare_buffer, [name, capacity])

    def create_declare_arena_storage(name, capacity) = build(:declare_arena_storage, [name, capacity])

    def create_scope(body) = build(:scope, [body])

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

    def create_index(base, index, type) = build(:index, [base, index, type])

    def create_binary(operator, left, right, type) = build(:binary, [operator, left, right, type])

    def create_unary(operator, operand, type) = build(:unary, [operator, operand, type])

    def create_call(name, arguments, type) = build(:call, [name, arguments, type])

    def create_function_reference(name) = build(:function_reference, [name, :function_reference])

    def create_cast(value, type) = build(:cast, [value, type])

    def create_size_of(target, type) = build(:size_of, [target, type])

    def create_brace_init(values, type) = build(:brace_init, [values, type])

    def replace_module(structs, functions)
      @tree = build(:module, [structs, functions])
      self
    end

    def structs = @tree[:children][0]

    def functions = @tree[:children][1]

    def node_type(node) = node[:type]

    def children_of(node) = node[:children]

    def value_type(node) = node[:children].last

    def function_name(function) = children_of(function)[0]

    def function_context(function) = children_of(function)[4]

    def function_body(function) = children_of(function)[3]

    def realtime_reachable_functions
      functions_by_name = functions.to_h { |function| [function_name(function), function] }
      reachable = []
      seen = {}
      realtime_functions.each do |function|
        collect_reachable_functions(function, functions_by_name, seen, reachable)
      end
      reachable
    end

    def arena_operation?(function)
      each_node(function_body(function)) do |node|
        return true if node_type(node) == :declare_arena_storage ||
                       (node_type(node) == :call && children_of(node)[0] == :bareruby_arena_alloc)
      end
      false
    end

    # What a program reaches for is asked of the IR rather than walked from outside it.
    # A build has three kinds of question — does this program call this function, does it
    # call anything from this family, does it contain this kind of node — and the shape a
    # node is stored in stays in here whichever is asked.
    def calls?(*names)
      any_node? { |node| node_type(node) == :call && names.include?(children_of(node)[0]) }
    end

    def calls_prefixed?(prefix)
      any_node? { |node| node_type(node) == :call && children_of(node)[0].to_s.start_with?(prefix) }
    end

    def contains?(type)
      any_node? { |node| node_type(node) == type }
    end

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
      name, parameters, return_type, body, context = function[:children]
      parameter_text = parameters.map { |parameter| "#{parameter[:name]}: #{type_text(parameter[:type])}" }.join(", ")
      ["function #{name}(#{parameter_text}) -> #{type_text(return_type)} [#{context}]"] +
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
      when :declare_arena_storage
        name, capacity = statement[:children]
        ["#{indent}declare_arena_storage #{name}[#{capacity}]"]
      when :scope
        ["#{indent}scope"] +
          statement[:children][0].flat_map { |child| inspect_statement(child, "#{indent}    ") }
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
      when :index
        base, index, = node[:children]
        "#{expression_text(base)}[#{expression_text(index)}]"
      when :binary
        operator, left, right, = node[:children]
        "(#{expression_text(left)} #{operator} #{expression_text(right)})"
      when :unary
        operator, operand, = node[:children]
        "(#{operator}#{expression_text(operand)})"
      when :call
        name, arguments, = node[:children]
        "#{name}(#{arguments.map { |argument| expression_text(argument) }.join(', ')})"
      when :function_reference then "&#{node[:children][0]}"
      when :cast
        value, type = node[:children]
        "(#{type_text(type)})#{expression_text(value)}"
      when :size_of
        "sizeof(#{type_text(node[:children][0])})"
      when :brace_init
        values, = node[:children]
        "{ #{values.map { |value| expression_text(value) }.join(', ')} }"
      end
    end

    def type_text(type)
      case type
      when Hash
        case type[:kind]
        when :pointer then "#{type_text(type[:target])}*"
        when :c_array then "#{type_text(type[:element])}[#{type[:capacity]}]"
        else "struct #{type[:name]}"
        end
      else
        type.to_s
      end
    end

    private

    def realtime_functions = functions.select { |function| function_context(function) == :realtime }

    def collect_reachable_functions(function, functions_by_name, seen, reachable)
      name = function_name(function)
      return if seen[name]

      seen[name] = true
      reachable << function
      each_node(function_body(function)) do |node|
        next unless node_type(node) == :call

        target = functions_by_name[children_of(node)[0]]
        collect_reachable_functions(target, functions_by_name, seen, reachable) if target
      end
    end

    def any_node?
      functions.each do |function|
        each_node(function_body(function)) { |node| return true if yield(node) }
      end
      false
    end

    def each_node(value, &block)
      return value.each { |element| each_node(element, &block) } if value.is_a?(Array)
      return unless value.is_a?(Hash)
      return value.each_value { |element| each_node(element, &block) } unless value.key?(:type)

      yield(value)
      each_node(children_of(value), &block)
    end

    def build(type, children) = { type:, children: }
  end
end
