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
require_relative "pass/pass_09_lir_generator"
require_relative "pass/pass_12_cpp_source_generator"

module BareRubyProt
  class Compiler
    DUMP_DIRECTORY = File.expand_path("dump", __dir__)
    BUILD_DIRECTORY = File.expand_path("build", __dir__)
    SOURCE_SCHEMA = "CPP"
    SCHEMAS = {
      BareRubyAST::SCHEMA => BareRubyAST,
      TIR::SCHEMA => TIR,
      LIR::SCHEMA => LIR
    }.freeze

    def initialize(source_file_name)
      @source_file_name = source_file_name
    end

    def run
      FileUtils.mkdir_p(DUMP_DIRECTORY)
      FileUtils.mkdir_p(BUILD_DIRECTORY)

      result = pass_01
      result = boundary("01_bareruby_ast", result)

      result = pass_02(result)
      result = boundary("02_bareruby_ast", result)

      result = pass_03(result)
      result = boundary("03_bareruby_ast", result)

      result = pass_05(result)
      result = boundary("05_typed_ir", result)

      result = pass_06(result)
      result = boundary("06_typed_ir", result)

      result = pass_07(result)
      result = boundary("07_typed_ir", result)

      result = pass_09(result)
      result = boundary("09_low_ir", result)

      result = pass_12(result)
      result = source_boundary("12_cpp_source", result)

      File.write(File.join(BUILD_DIRECTORY, "main.cpp"), result)

      0
    end

    def pass_01 = Pass::BareRubyAstGenerator.new(@source_file_name).run.result

    def pass_02(bareruby_ast) = Pass::Desugarer.new(bareruby_ast).run.result

    def pass_03(bareruby_ast) = Pass::LiteralFolder.new(bareruby_ast).run.result

    def pass_05(bareruby_ast) = Pass::TypeInferrer.new(bareruby_ast).run.result

    def pass_06(typed_ir) = Pass::BlockInliner.new(typed_ir).run.result

    def pass_07(typed_ir) = Pass::SymbolToIdConverter.new(typed_ir).run.result

    def pass_09(typed_ir) = Pass::LirGenerator.new(typed_ir).run.result

    def pass_12(low_ir) = Pass::CppSourceGenerator.new(low_ir).run.result

    def boundary(name, representation)
      write_binary_dump(name, representation.class::SCHEMA, representation.dump_payload)
      write_inspector_dump(name, representation.class::SCHEMA, "#{name}.txt", representation.inspect_text)
      restore(name)
    end

    def source_boundary(name, source_text)
      write_binary_dump(name, SOURCE_SCHEMA, source_text)
      write_inspector_dump(name, SOURCE_SCHEMA, "#{name}.cpp", source_text, "// ")
      restore(name)
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
      return envelope[:payload] if envelope[:schema] == SOURCE_SCHEMA

      SCHEMAS.fetch(envelope[:schema]).restore(envelope[:payload])
    end
  end
end

exit BareRubyProt::Compiler.new(ARGV[0] || File.expand_path("ref.rb", __dir__)).run
