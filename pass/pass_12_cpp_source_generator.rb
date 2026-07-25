# frozen_string_literal: true

module BareRubyProt
  module Pass
    class CppSourceGenerator
      PUTS_FUNCTIONS = %i[bareruby_puts_int32 bareruby_puts_int64].freeze

      RUNTIME_HEADER = <<~CPP
        #ifndef BARERUBY_RUNTIME_H
        #define BARERUBY_RUNTIME_H

        #include <stdint.h>

        #ifdef __cplusplus
        extern "C" {
        #endif

        void bareruby_puts_int32(int32_t value);
        void bareruby_puts_int64(int64_t value);

        #ifdef __cplusplus
        }
        #endif

        #endif
      CPP

      RUNTIME_STDIO_SOURCE = <<~CPP
        #include "bareruby_runtime.h"

        #include <stdio.h>

        void bareruby_puts_int32(int32_t value) {
            printf("%d\\n", (int)value);
        }

        void bareruby_puts_int64(int64_t value) {
            printf("%lld\\n", (long long)value);
        }
      CPP

      BINDING_HEADER = <<~CPP
        #ifndef BARERUBY_BINDING_H
        #define BARERUBY_BINDING_H

        #include <stdbool.h>
        #include <stdint.h>

        #ifdef __cplusplus
        extern "C" {
        #endif

        typedef struct {
            int32_t pin;
            int32_t params;
        } bareruby_gpio_t;

        void bareruby_startup(void);

        void bareruby_gpio_init(bareruby_gpio_t *self, int32_t pin, int32_t params);
        void bareruby_gpio_write(bareruby_gpio_t *self, int32_t value);
        int32_t bareruby_gpio_read(bareruby_gpio_t *self);
        bool bareruby_gpio_high(bareruby_gpio_t *self);
        bool bareruby_gpio_low(bareruby_gpio_t *self);

        void bareruby_sleep(int32_t seconds);
        void bareruby_sleep_ms(int32_t milliseconds);

        #ifdef __cplusplus
        }
        #endif

        #endif
      CPP

      BINDING_HOST_SOURCE = <<~CPP
        #include "bareruby_binding.h"

        #include <stdio.h>

        void bareruby_startup(void) {
            fprintf(stderr, "startup()\\n");
        }

        void bareruby_gpio_init(bareruby_gpio_t *self, int32_t pin, int32_t params) {
            self->pin = pin;
            self->params = params;
            fprintf(stderr, "gpio_init(pin=%d, params=%d)\\n", (int)pin, (int)params);
        }

        void bareruby_gpio_write(bareruby_gpio_t *self, int32_t value) {
            fprintf(stderr, "gpio_write(pin=%d, value=%d)\\n", (int)self->pin, (int)value);
        }

        int32_t bareruby_gpio_read(bareruby_gpio_t *self) {
            fprintf(stderr, "gpio_read(pin=%d) -> 0\\n", (int)self->pin);
            return 0;
        }

        bool bareruby_gpio_high(bareruby_gpio_t *self) {
            fprintf(stderr, "gpio_high(pin=%d) -> false\\n", (int)self->pin);
            return false;
        }

        bool bareruby_gpio_low(bareruby_gpio_t *self) {
            fprintf(stderr, "gpio_low(pin=%d) -> true\\n", (int)self->pin);
            return true;
        }

        void bareruby_sleep(int32_t seconds) {
            fprintf(stderr, "sleep(seconds=%d)\\n", (int)seconds);
        }

        void bareruby_sleep_ms(int32_t milliseconds) {
            fprintf(stderr, "sleep_ms(milliseconds=%d)\\n", (int)milliseconds);
        }
      CPP

      BINDING_RP2040_SOURCE = <<~CPP
        #include "bareruby_binding.h"

        #include "hardware/gpio.h"
        #include "pico/stdlib.h"

        void bareruby_startup(void) {
            stdio_init_all();
        }

        void bareruby_gpio_init(bareruby_gpio_t *self, int32_t pin, int32_t params) {
            self->pin = pin;
            self->params = params;
            gpio_init((uint)pin);
            gpio_set_dir((uint)pin, (params & 1) ? GPIO_OUT : GPIO_IN);
            if (params & 4) {
                gpio_pull_up((uint)pin);
            }
            if (params & 8) {
                gpio_pull_down((uint)pin);
            }
        }

        void bareruby_gpio_write(bareruby_gpio_t *self, int32_t value) {
            gpio_put((uint)self->pin, value != 0);
        }

        int32_t bareruby_gpio_read(bareruby_gpio_t *self) {
            return gpio_get((uint)self->pin) ? 1 : 0;
        }

        bool bareruby_gpio_high(bareruby_gpio_t *self) {
            return gpio_get((uint)self->pin);
        }

        bool bareruby_gpio_low(bareruby_gpio_t *self) {
            return !gpio_get((uint)self->pin);
        }

        void bareruby_sleep(int32_t seconds) {
            sleep_ms((uint32_t)seconds * 1000u);
        }

        void bareruby_sleep_ms(int32_t milliseconds) {
            sleep_ms((uint32_t)milliseconds);
        }
      CPP

      HOSTED_MANIFEST = <<~MANIFEST
        target = hosted
        toolchain = g++
        language_standard = gnu++20
        compile_options = -std=gnu++20 -fno-rtti
        include_directories = ..
        sources = main.cpp ../bareruby_binding_host.cpp ../bareruby_runtime_stdio.cpp
        link_libraries =
        stdout_channel = printf
        exceptions = enabled
        artifact = bareruby_program
        build_command = g++ -std=gnu++20 -fno-rtti -I.. -o bareruby_program main.cpp ../bareruby_binding_host.cpp ../bareruby_runtime_stdio.cpp
      MANIFEST

      attr_reader :result, :stdout_notice

      def initialize(low_ir, debug:)
        @lir = low_ir
        @debug = debug
        @stdout_notice = false
      end

      def run
        rp2040_program = program_source(:rp2040)
        @result = {
          "bareruby_runtime.h" => RUNTIME_HEADER,
          "bareruby_runtime_stdio.cpp" => RUNTIME_STDIO_SOURCE,
          "bareruby_binding.h" => BINDING_HEADER,
          "bareruby_binding_host.cpp" => BINDING_HOST_SOURCE,
          "bareruby_binding_rp2040.cpp" => BINDING_RP2040_SOURCE,
          "hosted/main.cpp" => program_source(:hosted),
          "hosted/manifest.txt" => HOSTED_MANIFEST,
          "rp2040/main.cpp" => rp2040_program,
          "rp2040/manifest.txt" => rp2040_manifest,
          "rp2040/CMakeLists.txt" => cmake_lists
        }

        self
      end

      def rp2040_sources
        sources = ["main.cpp", "../bareruby_binding_rp2040.cpp"]
        sources << "../bareruby_runtime_stdio.cpp" if @debug
        sources
      end

      def rp2040_manifest
        <<~MANIFEST
          target = freestanding-rp2040
          toolchain = arm-none-eabi-g++
          language_standard = gnu++20
          compile_options = -std=gnu++20 -fno-rtti
          include_directories = ..
          sources = #{rp2040_sources.join(' ')}
          link_libraries = pico_stdlib hardware_gpio
          stdout_channel = #{@debug ? 'usb' : 'none'}
          debug = #{@debug ? 'enabled' : 'disabled'}
          exceptions = enabled
          artifact = bareruby_program.uf2
          build_command = cmake -B build -S . && cmake --build build
        MANIFEST
      end

      def cmake_lists
        <<~CMAKE
          cmake_minimum_required(VERSION 3.13)

          include($ENV{PICO_SDK_PATH}/external/pico_sdk_import.cmake)

          project(bareruby_program C CXX ASM)
          set(CMAKE_C_STANDARD 11)
          set(CMAKE_CXX_STANDARD 20)

          pico_sdk_init()

          add_executable(bareruby_program
          #{rp2040_sources.map { |source| "    #{source}" }.join("\n")}
          )

          target_include_directories(bareruby_program PRIVATE ..)
          target_compile_options(bareruby_program PRIVATE -fno-rtti)
          target_link_libraries(bareruby_program pico_stdlib hardware_gpio)
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
        sections.concat(@lir.structs.map { |struct| struct_text(struct) })
        sections << "#{@lir.functions.map { |function| "#{signature_text(function)};" }.join("\n")}\n"
        sections.concat(@lir.functions.map { |function| function_text(function) })
        sections << entry_text(target)
        sections.join("\n")
      end

      def include_text(target)
        lines = ["#include <stdbool.h>", "#include <stdint.h>", "", "#include \"bareruby_binding.h\""]
        lines << "#include \"bareruby_runtime.h\"" if stdout_enabled?(target)
        "#{lines.join("\n")}\n"
      end

      def stdout_enabled?(target) = target == :hosted || @debug

      def entry_text(target)
        return "int main(void) {\n    bareruby_main();\n    return 0;\n}\n" if target == :hosted

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

      def pointer_type?(type) = type.is_a?(Hash) && type[:kind] == :pointer

      def declaration_text(type, name)
        pointer_type?(type) ? "#{type_text(type[:target])} *#{name}" : "#{type_text(type)} #{name}"
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
