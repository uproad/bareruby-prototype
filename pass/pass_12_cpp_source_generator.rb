# frozen_string_literal: true

module BareRubyProt
  module Pass
    class CppSourceGenerator
      PRELUDE = <<~CPP
        #include <stdint.h>
        #include <stdio.h>

        static void bareruby_puts_int32(int32_t value);
        static void bareruby_puts_int64(int64_t value);

        static void bareruby_puts_int32(int32_t value) {
            printf("%d\\n", (int)value);
        }

        static void bareruby_puts_int64(int64_t value) {
            printf("%lld\\n", (long long)value);
        }
      CPP

      EPILOGUE = <<~CPP
        int main(void) {
            bareruby_main();
            return 0;
        }
      CPP

      attr_reader :result

      def initialize(low_ir)
        @lir = low_ir
      end

      def run
        sections = [PRELUDE]
        sections.concat(@lir.structs.map { |struct| struct_text(struct) })
        sections << @lir.functions.map { |function| "#{signature_text(function)};" }.join("\n")
        sections.concat(@lir.functions.map { |function| function_text(function) })
        sections << EPILOGUE
        @result = sections.join("\n")

        self
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
        when :declare, :assign, :expression, :return
          ["#{indent}#{simple_statement_text(statement)};"]
        when :for
          init, condition, step, body = @lir.children_of(statement)
          header = "#{indent}for (#{simple_statement_text(init)}; " \
                   "#{expression_text(condition)}; #{simple_statement_text(step)}) {"
          [header] + body.flat_map { |child| statement_lines(child, "#{indent}    ") } + ["#{indent}}"]
        when :while
          condition, body = @lir.children_of(statement)
          ["#{indent}while (#{expression_text(condition)}) {"] +
            body.flat_map { |child| statement_lines(child, "#{indent}    ") } + ["#{indent}}"]
        when :break
          ["#{indent}break;"]
        when :next
          ["#{indent}continue;"]
        end
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
        when :local
          @lir.children_of(node)[0].to_s
        when :self_pointer
          "self"
        when :field_access
          base, name, = @lir.children_of(node)
          separator = @lir.value_type(base).is_a?(Hash) && @lir.value_type(base)[:kind] == :pointer ? "->" : "."
          "#{expression_text(base)}#{separator}#{name}"
        when :address_of
          "&#{expression_text(@lir.children_of(node)[0])}"
        when :binary
          operator, left, right, = @lir.children_of(node)
          "(#{expression_text(left)} #{operator} #{expression_text(right)})"
        when :unary
          operator, operand, = @lir.children_of(node)
          "(#{operator}#{expression_text(operand)})"
        when :call
          name, arguments, = @lir.children_of(node)
          "#{name}(#{arguments.map { |argument| expression_text(argument) }.join(', ')})"
        end
      end

      def declaration_text(type, name)
        type.is_a?(Hash) && type[:kind] == :pointer ? "#{type_text(type[:target])} *#{name}" : "#{type_text(type)} #{name}"
      end

      def type_text(type)
        case type
        when :int32 then "int32_t"
        when :int64 then "int64_t"
        when :bool then "bool"
        when :void then "void"
        when Hash
          type[:kind] == :pointer ? "#{type_text(type[:target])} *" : type[:name].to_s
        end
      end
    end
  end
end
