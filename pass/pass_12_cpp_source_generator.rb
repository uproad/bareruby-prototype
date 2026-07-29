# frozen_string_literal: true

require_relative "pass_12_cpp_source_generator/runtime_source"
require_relative "pass_12_cpp_source_generator/binding_declaration"
require_relative "pass_12_cpp_source_generator/host_binding_source"
require_relative "pass_12_cpp_source_generator/onboard_led_source"
require_relative "pass_12_cpp_source_generator/pico_binding_source"
require_relative "pass_12_cpp_source_generator/host_build"
require_relative "pass_12_cpp_source_generator/pico_build"

module BareRubyProt
  module Pass
    class CppSourceGenerator
      PUTS_FUNCTIONS = %i[
        bareruby_puts_int32 bareruby_puts_int64 bareruby_puts_string bareruby_puts_bool
        bareruby_puts_fixed bareruby_printf
      ].freeze

      attr_reader :result, :stdout_notice

      def initialize(low_ir, targets:, debug:, exceptions: true)
        @lir = low_ir
        @targets = targets
        @debug = debug
        @exceptions = exceptions
        @stdout_notice = false
      end

      def run
        @result = RuntimeSource::FILES.merge(BindingDeclaration::FILES)
        @result.merge!(HostBindingSource::FILES) if @targets.any?(&:hosted?)
        @result.merge!(PicoBindingSource::FILES) unless @targets.all?(&:hosted?)
        if lights_onboard_led?
          @targets.each { |target| @result.merge!(OnboardLedSource.files(target.led)) }
        end
        @targets.each { |target| @result.merge!(target_sources(target)) }

        self
      end

      # A program that never lights the LED links none of this, which matters most on a
      # wireless board: reaching that LED means uploading the radio's firmware.
      def lights_onboard_led? = @lir.calls_prefixed?("bareruby_onboard_led_")

      # Only a program that raises needs the throw translation unit linked.
      def throws? = @lir.calls?(:bareruby_throw)

      # A program with no arena never links the allocator, so a program that keeps to the
      # first two layers of the memory model pays nothing for the third.
      def allocates? = @lir.contains?(:declare_arena_storage)

      # A program that keeps to static and fixed-capacity strings never links the string
      # runtime either, which costs stdio's vsnprintf on top of the region it allocates
      # from. Receiving over UART or off the I2C bus answers a variable-length string, so
      # those reach it without naming it.
      def builds_strings?
        @lir.calls_prefixed?("bareruby_string_") ||
          @lir.calls?(:bareruby_uart_read, :bareruby_uart_gets, :bareruby_i2c_read)
      end

      def receives_uart? = @lir.calls?(:bareruby_uart_read, :bareruby_uart_gets)

      def uses_i2c? = @lir.calls_prefixed?("bareruby_i2c_")

      def reads_i2c? = @lir.calls?(:bareruby_i2c_read)

      # Each target owns a directory named after itself, holding the entry point, the
      # record of how it is built, and — for a board — the build system that does it.
      def target_sources(target)
        files = { "main.cpp" => program_source(target) }.merge(build_of(target).files)
        files.transform_keys { |name| "#{target.name}/#{name}" }
      end

      def build_of(target)
        return HostBuild.new(sources: sources(target)) if target.hosted?

        PicoBuild.new(target, sources: sources(target), onboard_led: lights_onboard_led?,
                              debug: @debug, exceptions: @exceptions)
      end

      # The entry point, then what a build of this kind always links, then the units this
      # program reaches for. Both kinds of machine take the same shape and differ only in
      # which binding answers, so one list serves both — and no file is named here, only
      # asked for.
      def sources(target)
        binding_source = target.hosted? ? HostBindingSource : PicoBindingSource
        names = binding_source::ALWAYS + RuntimeSource::ALWAYS
        names << binding_source::UART_RECEIVE_FILE if receives_uart?
        names << binding_source::I2C_FILE if uses_i2c?
        names << binding_source::I2C_READ_FILE if reads_i2c?
        names << OnboardLedSource.file_name(target.led) if lights_onboard_led?
        names << RuntimeSource::ARENA_FILE if allocates?
        names << RuntimeSource::STRING_FILE if builds_strings?
        names << RuntimeSource::THROW_FILE if throws?
        ["main.cpp"] + names.map { |name| "../#{name}" }
      end

      def program_source(target)
        @target = target
        sections = [include_text(target)]
        sections << "#{@lir.structs.map { |struct| "struct #{@lir.children_of(struct)[0]};" }.join("\n")}\n"
        sections.concat(@lir.structs.map { |struct| struct_text(struct) })
        sections << "#{@lir.functions.map { |function| "#{signature_text(function)};" }.join("\n")}\n"
        sections.concat(@lir.functions.map { |function| function_text(function) })
        sections << entry_text(target)
        sections.join("\n")
      end

      # The runtime header is always included: Fixed arithmetic is declared there and is
      # needed whether or not the build has a stdout channel.
      def include_text(_target)
        lines = ["#include <stdbool.h>", "#include <stdint.h>", "",
                 "#include \"bareruby_binding.h\"", "#include \"bareruby_runtime.h\""]
        "#{lines.join("\n")}\n"
      end

      def stdout_enabled?(target) = target.hosted? || @debug

      def entry_text(target)
        return "int main(void) {\n    bareruby_main();\n    return 0;\n}\n" if target.hosted?

        "int main(void) {\n    bareruby_startup();\n    bareruby_main();\n    for (;;) {\n" \
          "        bareruby_sleep_ms(1000);\n    }\n}\n"
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
        if !stdout_enabled?(@target) && @lir.node_type(value) == :call &&
           PUTS_FUNCTIONS.include?(@lir.children_of(value)[0])
          @stdout_notice = true
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
          "(#{type_text(type)})#{expression_text(value)}"
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
end
