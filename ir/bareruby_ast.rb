# frozen_string_literal: true

module BareRubyProt
  class BareRubyAST
    SCHEMA = "BRAST"

    def self.restore(payload)
      ast = allocate
      ast.install(payload)
      ast
    end

    def initialize(filename)
      @filename = filename
      @tree = build(:program, [[]], create_span(0, 1, 0, 0, 1, 0))
    end

    def install(payload)
      @filename = payload[:filename]
      @tree = payload[:tree]
    end

    def dump_payload
      { filename: @filename, tree: @tree }
    end

    def create_span(start_offset, start_line, start_column, end_offset, end_line, end_column)
      {
        filename: @filename,
        start: { offset: start_offset, line: start_line, column: start_column },
        end: { offset: end_offset, line: end_line, column: end_column }
      }
    end

    def create_integer(value, span) = build(:integer, [value], span)

    def create_nil(span) = build(:nil, [], span)

    def create_reference(kind, name, span) = build(:reference, [kind, name], span)

    def create_constant_path(owner, name, span) = build(:constant_path, [owner, name], span)

    def create_boolean(value, span) = build(:boolean, [value], span)

    def create_string(value, span) = build(:string, [value], span)

    def create_symbol(name, span) = build(:symbol, [name], span)

    def create_float(value, span) = build(:float, [value], span)

    def create_interpolation(parts, span) = build(:interpolation, [parts], span)

    def create_array(elements, span) = build(:array, [elements], span)

    def create_keyword_argument(name, value, span) = build(:keyword_argument, [name, value], span)

    def create_if(condition, then_body, else_body, span)
      build(:if, [condition, then_body, else_body], span)
    end

    def create_while(condition, body, span) = build(:while, [condition, body], span)

    def create_logical(operator, left, right, span) = build(:logical, [operator, left, right], span)

    def create_assignment(target, value, span) = build(:assignment, [target, value], span)

    def create_compound_assignment(target, operator, value, span)
      build(:compound_assignment, [target, operator, value], span)
    end

    def create_parameter(name, span) = build(:parameter, [name], span)

    def create_method_definition(name, parameters, body, span)
      build(:method_definition, [name, parameters, body], span)
    end

    def create_subclass_definition(name, superclass, body, span)
      build(:subclass_definition, [name, superclass, body], span)
    end

    def create_class_definition(name, body, span) = build(:class_definition, [name, body], span)

    def create_module_definition(name, body, span) = build(:module_definition, [name, body], span)

    def create_super(arguments, span) = build(:super, [arguments], span)

    def create_begin(body, rescue_body, span) = build(:begin, [body, rescue_body], span)

    def create_call(receiver, name, arguments, block, span)
      build(:call, [receiver, name, arguments, block], span)
    end

    def create_block(parameters, body, span) = build(:block, [parameters, body], span)

    def create_return(value, span) = build(:return, [value], span)

    def create_iteration_control(kind, span) = build(:iteration_control, [kind], span)

    def replace_program(body, span)
      @tree = build(:program, [body], span)
      self
    end

    def program_body = @tree[:children][0]

    def program_span = @tree[:span]

    def node_type(node) = node[:type]

    def children_of(node) = node[:children]

    def span_of(node) = node[:span]

    def inspect_text
      program_body.flat_map { |statement| inspect_lines(statement, "") }.join("\n")
    end

    def inspect_lines(node, indent)
      case node[:type]
      when :subclass_definition
        name, superclass, body = node[:children]
        [gutter(node) + "#{indent}subclass_definition(#{name.inspect}, #{superclass.inspect})"] +
          body.flat_map { |statement| inspect_lines(statement, "#{indent}  ") }
      when :class_definition
        name, body = node[:children]
        [gutter(node) + "#{indent}class_definition(#{name.inspect})"] +
          body.flat_map { |statement| inspect_lines(statement, "#{indent}  ") }
      when :begin
        body, rescue_body = node[:children]
        lines = [gutter(node) + indent + "begin"] + body.flat_map { |s| inspect_lines(s, indent + "  ") }
        lines << gutter(node) + indent + "rescue"
        lines + rescue_body.flat_map { |s| inspect_lines(s, indent + "  ") }
      when :module_definition
        name, body = node[:children]
        [gutter(node) + "#{indent}module_definition(#{name.inspect})"] +
          body.flat_map { |statement| inspect_lines(statement, "#{indent}  ") }
      when :method_definition
        name, parameters, body = node[:children]
        parameter_text = parameters.map { |parameter| inspect_inline(parameter) }.join(", ")
        [gutter(node) + "#{indent}method_definition(#{name.inspect}, [#{parameter_text}])"] +
          body.flat_map { |statement| inspect_lines(statement, "#{indent}  ") }
      when :if
        condition, then_body, else_body = node[:children]
        lines = [gutter(node) + "#{indent}if(#{inspect_inline(condition)})"]
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
      when :call
        block = node[:children][3]
        header = [gutter(node) + "#{indent}#{inspect_inline(node)}"]
        block ? header + block[:children][1].flat_map { |statement| inspect_lines(statement, "#{indent}  ") } : header
      when :assignment
        target, value = node[:children]
        if value[:type] == :call && value[:children][3]
          [gutter(node) + "#{indent}assignment(#{inspect_inline(target)}, #{inspect_inline(value)})"] +
            value[:children][3][:children][1].flat_map { |statement| inspect_lines(statement, "#{indent}  ") }
        else
          [gutter(node) + "#{indent}#{inspect_inline(node)}"]
        end
      else
        [gutter(node) + "#{indent}#{inspect_inline(node)}"]
      end
    end

    def inspect_inline(node)
      case node[:type]
      when :integer
        "integer(#{node[:children][0].inspect})"
      when :reference
        kind, name = node[:children]
        "reference(#{kind.inspect}, #{name.inspect})"
      when :constant_path
        owner, name = node[:children]
        "constant_path(#{owner.inspect}, #{name.inspect})"
      when :boolean
        "boolean(#{node[:children][0].inspect})"
      when :string
        "string(#{node[:children][0].inspect})"
      when :symbol
        "symbol(#{node[:children][0].inspect})"
      when :float
        "float(#{node[:children][0].inspect})"
      when :interpolation
        "interpolation(#{node[:children][0].map { |part| inspect_inline(part) }.join(', ')})"
      when :array
        "array([#{node[:children][0].map { |element| inspect_inline(element) }.join(', ')}])"
      when :keyword_argument
        name, value = node[:children]
        "keyword_argument(#{name.inspect}, #{inspect_inline(value)})"
      when :logical
        operator, left, right = node[:children]
        "logical(#{operator.inspect}, #{inspect_inline(left)}, #{inspect_inline(right)})"
      when :if
        condition, = node[:children]
        "if(#{inspect_inline(condition)})"
      when :while
        condition, = node[:children]
        "while(#{inspect_inline(condition)})"
      when :parameter
        "parameter(#{node[:children][0].inspect})"
      when :assignment
        target, value = node[:children]
        "assignment(#{inspect_inline(target)}, #{inspect_inline(value)})"
      when :compound_assignment
        target, operator, value = node[:children]
        "compound_assignment(#{inspect_inline(target)}, #{operator.inspect}, #{inspect_inline(value)})"
      when :return
        value = node[:children][0]
        "return(#{value ? inspect_inline(value) : 'nil'})"
      when :iteration_control
        "iteration_control(#{node[:children][0].inspect})"
      when :super
        "super([#{node[:children][0].map { |argument| inspect_inline(argument) }.join(', ')}])"
      when :call
        receiver, name, arguments, block = node[:children]
        parts = [receiver ? inspect_inline(receiver) : "nil", name.inspect]
        parts << "[#{arguments.map { |argument| inspect_inline(argument) }.join(', ')}]"
        if block
          parameters = block[:children][0]
          parts << "block(#{parameters.map { |parameter| inspect_inline(parameter) }.join(', ')})"
        end
        "call(#{parts.join(', ')})"
      end
    end

    def gutter(node)
      format("%3d| ", node[:span][:start][:line])
    end

    private

    def build(type, children, span) = { type:, children:, span: }
  end
end
