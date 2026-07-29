# frozen_string_literal: true

require_relative "../runtime/source_set"

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
        @source_set = SourceSet.new(targets:, onboard_led: lights_onboard_led?)
      end

      def run
        @result = @source_set.files
        @targets.each { |target| @result.merge!(target_sources(target)) }

        self
      end

      def onboard_led_source_of(target) = @source_set.onboard_led_file_name(target)

      # A program that never lights the LED links none of this, which matters most on a
      # wireless board: reaching that LED means uploading the radio's firmware.
      def lights_onboard_led?
        @lir.functions.any? { |function| calls_onboard_led?(@lir.children_of(function)[3]) }
      end

      def calls_onboard_led?(value)
        return value.any? { |element| calls_onboard_led?(element) } if value.is_a?(Array)
        return false unless value.is_a?(Hash)
        return true if value[:type] == :call && value[:children][0].to_s.start_with?("bareruby_onboard_led_")

        calls_onboard_led?(value[:children])
      end

      # Each target owns a directory named after itself, holding the entry point, the
      # record of how it is built, and — for a board — the build system that does it.
      def target_sources(target)
        sources = {
          "#{target.name}/main.cpp" => program_source(target),
          "#{target.name}/manifest.txt" => manifest(target)
        }
        sources["#{target.name}/CMakeLists.txt"] = cmake_lists(target) unless target.hosted?
        sources
      end

      def manifest(target) = target.hosted? ? hosted_manifest : pico_manifest(target)

      def hosted_sources
        sources = ["main.cpp", "../bareruby_binding_host.cpp", "../bareruby_runtime_fixed.cpp",
                   "../bareruby_runtime_stdio.cpp"]
        sources << "../bareruby_binding_uart_receive_host.cpp" if receives_uart?
        sources << "../bareruby_binding_i2c_host.cpp" if uses_i2c?
        sources << "../bareruby_binding_i2c_read_host.cpp" if reads_i2c?
        sources << "../bareruby_binding_onboard_led_host.cpp" if lights_onboard_led?
        sources << "../bareruby_runtime_arena.cpp" if allocates?
        sources << "../bareruby_runtime_string.cpp" if builds_strings?
        sources << "../bareruby_runtime_throw.cpp" if throws?
        sources
      end

      def hosted_manifest
        <<~MANIFEST
          target = host
          toolchain = g++
          language_standard = gnu++20
          compile_options = -std=gnu++20 -fno-rtti
          include_directories = ..
          sources = #{hosted_sources.join(' ')}
          link_libraries =
          stdout_channel = printf
          exceptions = enabled
          artifact = bareruby_program
          build_command = g++ -std=gnu++20 -fno-rtti -I.. -o bareruby_program #{hosted_sources.join(' ')}
        MANIFEST
      end

      # Only a program that raises needs the throw translation unit linked.
      def throws?
        @lir.functions.any? { |function| calls_throw?(@lir.children_of(function)[3]) }
      end

      def calls_throw?(value)
        return value.any? { |element| calls_throw?(element) } if value.is_a?(Array)
        return false unless value.is_a?(Hash)
        return true if value[:type] == :call && value[:children][0] == :bareruby_throw

        calls_throw?(value[:children])
      end

      # A program with no arena never links the allocator, so a program that keeps to the
      # first two layers of the memory model pays nothing for the third.
      def allocates?
        @lir.functions.any? { |function| declares_arena?(@lir.children_of(function)[3]) }
      end

      def declares_arena?(value)
        return value.any? { |element| declares_arena?(element) } if value.is_a?(Array)
        return false unless value.is_a?(Hash)
        return true if value[:type] == :declare_arena_storage

        declares_arena?(value[:children])
      end

      # A program that keeps to static and fixed-capacity strings never links the string
      # runtime either, which costs stdio's vsnprintf on top of the region it allocates from.
      def builds_strings?
        @lir.functions.any? { |function| calls_string?(@lir.children_of(function)[3]) }
      end

      def calls_string?(value)
        return value.any? { |element| calls_string?(element) } if value.is_a?(Array)
        return false unless value.is_a?(Hash)
        if value[:type] == :call
          function = value[:children][0]
          return true if function.to_s.start_with?("bareruby_string_") ||
                         %i[bareruby_uart_read bareruby_uart_gets bareruby_i2c_read].include?(function)
        end

        calls_string?(value[:children])
      end

      def receives_uart?
        @lir.functions.any? { |function| calls_uart_receive?(@lir.children_of(function)[3]) }
      end

      def calls_uart_receive?(value)
        return value.any? { |element| calls_uart_receive?(element) } if value.is_a?(Array)
        return false unless value.is_a?(Hash)
        return true if value[:type] == :call &&
                       %i[bareruby_uart_read bareruby_uart_gets].include?(value[:children][0])

        calls_uart_receive?(value[:children])
      end

      def uses_i2c?
        @lir.functions.any? { |function| calls_i2c?(@lir.children_of(function)[3]) }
      end

      def calls_i2c?(value)
        return value.any? { |element| calls_i2c?(element) } if value.is_a?(Array)
        return false unless value.is_a?(Hash)
        return true if value[:type] == :call &&
                       value[:children][0].to_s.start_with?("bareruby_i2c_")

        calls_i2c?(value[:children])
      end

      def reads_i2c?
        @lir.functions.any? { |function| calls_i2c_read?(@lir.children_of(function)[3]) }
      end

      def calls_i2c_read?(value)
        return value.any? { |element| calls_i2c_read?(element) } if value.is_a?(Array)
        return false unless value.is_a?(Hash)
        return true if value[:type] == :call && value[:children][0] == :bareruby_i2c_read

        calls_i2c_read?(value[:children])
      end

      def pico_sources(target)
        sources = ["main.cpp", "../bareruby_binding_pico.cpp", "../bareruby_runtime_fixed.cpp",
                   "../bareruby_runtime_stdio.cpp"]
        sources << "../bareruby_binding_uart_receive_pico.cpp" if receives_uart?
        sources << "../bareruby_binding_i2c_pico.cpp" if uses_i2c?
        sources << "../bareruby_binding_i2c_read_pico.cpp" if reads_i2c?
        sources << "../#{onboard_led_source_of(target)}" if lights_onboard_led?
        sources << "../bareruby_runtime_arena.cpp" if allocates?
        sources << "../bareruby_runtime_string.cpp" if builds_strings?
        sources << "../bareruby_runtime_throw.cpp" if throws?
        sources
      end

      # The radio's driver is linked only by a wireless board that actually lights its
      # LED, so the firmware blob it carries is not a tax on every build for that board.
      def pico_libraries(target)
        libraries = %w[pico_stdlib hardware_adc hardware_gpio hardware_pwm hardware_uart
                       hardware_i2c hardware_clocks]
        libraries << "pico_cyw43_arch_none" if target.led == :wireless && lights_onboard_led?
        libraries
      end

      def pico_manifest(target)
        <<~MANIFEST
          target = #{target.name}
          board = #{target.board}
          platform = #{target.platform}
          toolchain = arm-none-eabi-g++
          language_standard = gnu++20
          compile_options = -std=gnu++20 -fno-rtti
          include_directories = ..
          sources = #{pico_sources(target).join(' ')}
          link_libraries = #{pico_libraries(target).join(' ')}
          stdout_channel = #{@debug ? 'usb' : 'none'}
          debug = #{@debug ? 'enabled' : 'disabled'}
          exceptions = #{@exceptions ? 'enabled' : 'disabled'}
          artifact = bareruby_program.uf2
          build_command = cmake -B build -S . && cmake --build build
        MANIFEST
      end

      def cmake_lists(target)
        <<~CMAKE
          cmake_minimum_required(VERSION 3.13)

          # The board picks the chip, the linker script and the register headers, so it has
          # to be set before the SDK is imported rather than passed to the build later.
          set(PICO_BOARD #{target.board})
          set(PICO_PLATFORM #{target.platform})

          include($ENV{PICO_SDK_PATH}/external/pico_sdk_import.cmake)

          # pico-sdk leaves C++ exceptions off unless asked, so whether the unwinder and
          # its tables are linked is a decision the first stage records here.
          set(PICO_CXX_ENABLE_EXCEPTIONS #{@exceptions ? 1 : 0})

          project(bareruby_program C CXX ASM)
          set(CMAKE_C_STANDARD 11)
          set(CMAKE_CXX_STANDARD 20)

          pico_sdk_init()

          add_executable(bareruby_program
          #{pico_sources(target).map { |source| "    #{source}" }.join("\n")}
          )

          target_include_directories(bareruby_program PRIVATE ..)
          target_compile_options(bareruby_program PRIVATE $<$<COMPILE_LANGUAGE:CXX>:-fno-rtti#{@exceptions ? '' : ' -fno-exceptions'}>)
          target_link_libraries(bareruby_program #{pico_libraries(target).join(' ')})
          #{cmake_stdio_text}
          pico_add_extra_outputs(bareruby_program)
        CMAKE
      end

      def cmake_stdio_text
        return "\npico_enable_stdio_usb(bareruby_program 0)\npico_enable_stdio_uart(bareruby_program 0)\n" unless @debug

        <<~CMAKE

          pico_enable_stdio_usb(bareruby_program 1)
          pico_enable_stdio_uart(bareruby_program 0)

          # Keep the USB device enumerated so the board can be reset into BOOTSEL from
          # the host instead of by replugging it with the button held.
          target_compile_definitions(bareruby_program PRIVATE
              PICO_STDIO_USB_ENABLE_RESET_VIA_BAUD_RATE=1
              PICO_STDIO_USB_RESET_MAGIC_BAUD_RATE=1200
              PICO_STDIO_USB_ENABLE_RESET_VIA_VENDOR_INTERFACE=1
          )
        CMAKE
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
