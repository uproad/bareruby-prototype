#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"

require_relative "ir/bareruby_ast"
require_relative "ir/tir"
require_relative "ir/lir"
require_relative "pass/pass_01_bareruby_ast_generator"
require_relative "pass/pass_02_desugarer"
require_relative "pass/pass_03_literal_folder"
require_relative "pass/pass_05_type_inferrer"
require_relative "pass/pass_06_block_inliner"
require_relative "pass/pass_07_symbol_to_id_converter"
require_relative "pass/pass_08_typed_constant_folder"
require_relative "pass/pass_09_lir_generator"
require_relative "pass/pass_12_cpp_source_generator"

module BareRubyProt
  class Compiler
    DUMP_DIRECTORY = File.expand_path("dump", __dir__)
    BUILD_DIRECTORY = File.expand_path("build", __dir__)
    ARTIFACT_SCHEMA = "ARTIFACTS"
    STATUS_COMPILE_ERROR = 10
    BEGIN_ERROR = "error: begin requires the exception mechanism, which --no-exceptions removes."
    STDOUT_NOTICE = "notice: puts is not emitted in the freestanding build (stdout_channel = none). " \
                    "Enable a stdout channel to observe it."
    SCHEMAS = {
      BareRubyAST::SCHEMA => BareRubyAST,
      TIR::SCHEMA => TIR,
      LIR::SCHEMA => LIR
    }.freeze

    def initialize(source_file_name, debug:, exceptions:)
      @source_file_name = source_file_name
      @debug = debug
      @exceptions = exceptions
    end

    def run
      FileUtils.mkdir_p(DUMP_DIRECTORY)
      FileUtils.rm_rf(BUILD_DIRECTORY)
      FileUtils.mkdir_p(BUILD_DIRECTORY)

      generator = Pass::BareRubyAstGenerator.new(@source_file_name).run
      generator.notices.each { |notice| warn notice }
      result = generator.result
      result = boundary("01_bareruby_ast", result)

      result = pass_02(result)
      result = boundary("02_bareruby_ast", result)

      result = pass_03(result)
      result = boundary("03_bareruby_ast", result)

      reject_begin_without_exceptions(result)

      result = pass_05(result)
      result = boundary("05_typed_ir", result)

      result = pass_06(result)
      result = boundary("06_typed_ir", result)

      result = pass_07(result)
      result = boundary("07_typed_ir", result)

      result = pass_08(result)
      result = boundary("08_typed_ir", result)

      result = pass_09(result)
      result = boundary("09_low_ir", result)

      generator = pass_12(result)
      warn STDOUT_NOTICE if generator.stdout_notice
      artifacts = artifact_boundary("12_artifacts", generator.result)

      write_artifacts(artifacts)

      0
    end

    def write_artifacts(artifacts)
      artifacts.each do |relative_path, content|
        path = File.join(BUILD_DIRECTORY, relative_path)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
      end
    end

    def pass_01 = Pass::BareRubyAstGenerator.new(@source_file_name).run.result

    def pass_02(bareruby_ast) = Pass::Desugarer.new(bareruby_ast).run.result

    def pass_03(bareruby_ast) = Pass::LiteralFolder.new(bareruby_ast).run.result

    def pass_05(bareruby_ast) = Pass::TypeInferrer.new(bareruby_ast).run.result

    def pass_06(typed_ir) = Pass::BlockInliner.new(typed_ir).run.result

    def pass_07(typed_ir) = Pass::SymbolToIdConverter.new(typed_ir).run.result

    def pass_08(typed_ir) = Pass::TypedConstantFolder.new(typed_ir).run.result

    def pass_09(typed_ir) = Pass::LirGenerator.new(typed_ir).run.result

    def pass_12(low_ir) = Pass::CppSourceGenerator.new(low_ir, debug: @debug, exceptions: @exceptions).run

    # --no-exceptions removes the mechanism, so begin has nothing to land on and is
    # rejected outright rather than quietly doing nothing.
    def reject_begin_without_exceptions(bareruby_ast)
      return if @exceptions
      return unless Pass::TypeInferrer.new(bareruby_ast).contains_begin?(bareruby_ast.program_body)

      warn BEGIN_ERROR
      exit STATUS_COMPILE_ERROR
    end

    def boundary(name, representation)
      write_binary_dump(name, representation.class::SCHEMA, representation.dump_payload)
      write_inspector_dump(name, representation.class::SCHEMA, "#{name}.txt", representation.inspect_text)
      restore(name)
    end

    def artifact_boundary(name, artifacts)
      write_binary_dump(name, ARTIFACT_SCHEMA, artifacts)
      write_inspector_dump(name, ARTIFACT_SCHEMA, "#{name}.txt", artifact_inspector_text(artifacts))
      restore(name)
    end

    def artifact_inspector_text(artifacts)
      artifacts.map { |path, content| "--- file: #{path} ---\n#{content}" }.join("\n")
    end

    def write_binary_dump(name, schema, payload)
      envelope = { boundary: name, schema:, version: 1, payload: }
      File.binwrite(File.join(DUMP_DIRECTORY, "#{name}.bin"), Marshal.dump(envelope))
    end

    def write_inspector_dump(name, schema, file_name, body, comment_prefix = "")
      header = "#{comment_prefix}=== boundary: #{name} / schema: #{schema} / version: 1 ===\n"
      File.write(File.join(DUMP_DIRECTORY, file_name), "#{header}#{body}\n")
    end

    def restore(name)
      envelope = Marshal.load(File.binread(File.join(DUMP_DIRECTORY, "#{name}.bin")))
      return envelope[:payload] if envelope[:schema] == ARTIFACT_SCHEMA

      SCHEMAS.fetch(envelope[:schema]).restore(envelope[:payload])
    end
  end
end

arguments = ARGV.dup
debug = [arguments.delete("-d"), arguments.delete("--debug")].any?
exceptions = arguments.delete("--no-exceptions").nil?
source_file_name = arguments[0] || File.expand_path("ref.rb", __dir__)

exit BareRubyProt::Compiler.new(source_file_name, debug:, exceptions:).run
