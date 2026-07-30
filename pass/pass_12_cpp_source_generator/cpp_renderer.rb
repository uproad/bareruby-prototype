# frozen_string_literal: true

require_relative "binding_declaration"
require_relative "runtime_source"

module BareRubyProt
  # Renders one program as C++: the low-level IR written out as declarations, structs and
  # functions, with the entry point the machine it is built for asks for. A build with no
  # stdout channel drops the output calls rather than emitting calls that reach nothing,
  # and says so.
  class CppRenderer
    def initialize(low_ir, stdout:, entry:)
      @lir = low_ir
      @stdout = stdout
      @entry = entry
      @dropped_puts = false
    end

    attr_reader :dropped_puts

    def text
      sections = [include_text]
      sections << "#{@lir.structs.map { |struct| "struct #{@lir.children_of(struct)[0]};" }.join("\n")}\n"
      sections.concat(@lir.structs.map { |struct| struct_text(struct) })
      sections << "#{@lir.functions.map { |function| "#{signature_text(function)};" }.join("\n")}\n"
      sections.concat(@lir.functions.map { |function| function_text(function) })
      sections << @entry
      sections.join("\n")
    end

    # The runtime header is always included: Fixed arithmetic is declared there and is
    # needed whether or not the build has a stdout channel.
    def include_text
      lines = ["#include <stdbool.h>", "#include <stdint.h>", "",
               "#include \"#{BindingDeclaration::HEADER_FILE}\"", "#include \"#{RuntimeSource::HEADER_FILE}\""]
      "#{lines.join("\n")}\n"
    end

    def struct_text(struct)
      name, fields = @lir.children_of(struct)
      lines = ["struct #{name} {"]
      lines += fields.map { |field| "    #{declaration_text(field[:type], field[:name])};" }
      lines << "};\n"
      lines.join("\n")
    end

    def signature_text(function)
      name, parameters, return_type, = @lir.children_of(function)
      parameter_text =
        if parameters.empty?
          "void"
        else
          parameters.map { |parameter| declaration_text(parameter[:type], parameter[:name]) }.join(", ")
        end
      "static #{type_text(return_type)} #{name}(#{parameter_text})"
    end

    def function_text(function)
      body = @lir.children_of(function)[3]
      lines = ["#{signature_text(function)} {"]
      lines += body.flat_map { |statement| statement_lines(statement, "    ") }
      lines << "}\n"
      lines.join("\n")
    end

    def statement_lines(statement, indent)
      case @lir.node_type(statement)
      when :declare, :assign, :return
        ["#{indent}#{simple_statement_text(statement)};"]
      when :declare_buffer
        name, capacity = @lir.children_of(statement)
        ["#{indent}char #{name}[#{capacity}];"]
      when :declare_arena_storage
        name, capacity = @lir.children_of(statement)
        ["#{indent}static unsigned char #{name}[#{capacity}];"]
      when :scope
        ["#{indent}{"] +
          @lir.children_of(statement)[0].flat_map { |child| statement_lines(child, "#{indent}    ") } +
          ["#{indent}}"]
      when :expression
        expression_statement_lines(statement, indent)
      when :for
        init, condition, step, body = @lir.children_of(statement)
        header = "#{indent}for (#{simple_statement_text(init)}; " \
                 "#{expression_text(condition)}; #{simple_statement_text(step)}) {"
        [header] + body.flat_map { |child| statement_lines(child, "#{indent}    ") } + ["#{indent}}"]
      when :while
        condition, body = @lir.children_of(statement)
        ["#{indent}while (#{expression_text(condition)}) {"] +
          body.flat_map { |child| statement_lines(child, "#{indent}    ") } + ["#{indent}}"]
      when :if
        condition, then_body, else_body = @lir.children_of(statement)
        lines = ["#{indent}if (#{expression_text(condition)}) {"] +
                then_body.flat_map { |child| statement_lines(child, "#{indent}    ") }
        if else_body
          lines << "#{indent}} else {"
          lines += else_body.flat_map { |child| statement_lines(child, "#{indent}    ") }
        end
        lines + ["#{indent}}"]
      when :try
        body, rescue_body = @lir.children_of(statement)
        ["#{indent}try {"] + body.flat_map { |child| statement_lines(child, "#{indent}    ") } +
          ["#{indent}} catch (...) {"] +
          rescue_body.flat_map { |child| statement_lines(child, "#{indent}    ") } + ["#{indent}}"]
      when :break
        ["#{indent}break;"]
      when :next
        ["#{indent}continue;"]
      end
    end

    def expression_statement_lines(statement, indent)
      value = @lir.children_of(statement)[0]
      if !@stdout && @lir.node_type(value) == :call &&
         RuntimeSource::PUTS_FUNCTIONS.include?(@lir.children_of(value)[0])
        @dropped_puts = true
        return []
      end

      ["#{indent}#{expression_text(value)};"]
    end

    def simple_statement_text(statement)
      case @lir.node_type(statement)
      when :declare
        name, type, value = @lir.children_of(statement)
        text = declaration_text(type, name)
        value ? "#{text} = #{expression_text(value)}" : text
      when :assign
        place, value = @lir.children_of(statement)
        "#{expression_text(place)} = #{expression_text(value)}"
      when :expression
        expression_text(@lir.children_of(statement)[0])
      when :return
        value = @lir.children_of(statement)[0]
        value ? "return #{expression_text(value)}" : "return"
      end
    end

    def expression_text(node)
      case @lir.node_type(node)
      when :const_int
        value, type = @lir.children_of(node)
        type == :int64 ? "#{value}LL" : value.to_s
      when :const_bool
        @lir.children_of(node)[0].to_s
      when :const_string
        string_literal(@lir.children_of(node)[0])
      when :local
        @lir.children_of(node)[0].to_s
      when :self_pointer
        "self"
      when :field_access
        base, name, = @lir.children_of(node)
        separator = pointer_type?(@lir.value_type(base)) ? "->" : "."
        "#{expression_text(base)}#{separator}#{name}"
      when :address_of
        "&#{expression_text(@lir.children_of(node)[0])}"
      when :index
        base, index, = @lir.children_of(node)
        "#{expression_text(base)}[#{expression_text(index)}]"
      when :binary
        operator, left, right, = @lir.children_of(node)
        "(#{expression_text(left)} #{operator} #{expression_text(right)})"
      when :unary
        operator, operand, = @lir.children_of(node)
        "(#{operator}#{expression_text(operand)})"
      when :call
        name, arguments, = @lir.children_of(node)
        "#{name}(#{arguments.map { |argument| expression_text(argument) }.join(', ')})"
      when :function_reference
        "&#{@lir.children_of(node)[0]}"
      when :cast
        value, type = @lir.children_of(node)
        # Parenthesised because a cast binds looser than the indexing and the member
        # access that follow it.
        "((#{type_text(type)})#{expression_text(value)})"
      when :size_of
        "(int32_t)sizeof(#{type_text(@lir.children_of(node)[0])})"
      when :brace_init
        values, = @lir.children_of(node)
        "{ #{values.map { |value| expression_text(value) }.join(', ')} }"
      end
    end

    def pointer_type?(type) = type.is_a?(Hash) && type[:kind] == :pointer

    def declaration_text(type, name)
      return "#{type_text(type[:target])} *#{name}" if pointer_type?(type)
      return "#{type_text(type[:element])} #{name}[#{type[:capacity]}]" if c_array_type?(type)

      "#{type_text(type)} #{name}"
    end

    def c_array_type?(type) = type.is_a?(Hash) && type[:kind] == :c_array

    def string_literal(value)
      bytes = value.b.bytes.map do |byte|
        case byte
        when 34 then '\\"'
        when 92 then "\\\\"
        when 10 then "\\n"
        when 9 then "\\t"
        when 13 then "\\r"
        when 32..126 then byte.chr
        else format("\\%03o", byte)
        end
      end
      "\"#{bytes.join}\""
    end

    def type_text(type)
      case type
      when :int32 then "int32_t"
      when :int64 then "int64_t"
      when :uint8 then "unsigned char"
      when :bool then "bool"
      when :fixed then "int32_t"
      when :string_ptr then "const char *"
      when :void then "void"
      when Hash
        type[:kind] == :pointer ? "#{type_text(type[:target])} *" : type[:name].to_s
      end
    end
  end
end
