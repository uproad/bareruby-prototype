# frozen_string_literal: true

require_relative "pass_12_cpp_source_generator/runtime_source"
require_relative "pass_12_cpp_source_generator/binding_declaration"
require_relative "pass_12_cpp_source_generator/host_binding_source"
require_relative "pass_12_cpp_source_generator/onboard_led_source"
require_relative "pass_12_cpp_source_generator/pico_binding_source"
require_relative "pass_12_cpp_source_generator/host_build"
require_relative "pass_12_cpp_source_generator/pico_build"
require_relative "pass_12_cpp_source_generator/cpp_renderer"

module BareRubyProt
  module Pass
    class CppSourceGenerator
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
        build = build_of(target)
        files = { "main.cpp" => program_text(build) }.merge(build.files)
        files.transform_keys { |name| "#{target.name}/#{name}" }
      end

      def program_text(build)
        renderer = CppRenderer.new(@lir, stdout: build.stdout?, entry: build.entry)
        text = renderer.text
        @stdout_notice ||= renderer.dropped_puts
        text
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
    end
  end
end
