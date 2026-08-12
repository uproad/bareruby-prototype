# frozen_string_literal: true

require "fileutils"

require_relative "target/target"
require_relative "ir/bareruby_ast"
require_relative "ir/typed_ast"
require_relative "ir/lir"
require_relative "pass/pass_01_bareruby_ast_generator"
require_relative "pass/pass_02_desugarer"
require_relative "pass/pass_03_literal_folder"
require_relative "pass/pass_05_type_inferrer"
require_relative "pass/pass_06_block_inliner"
require_relative "pass/pass_07_symbol_to_id_converter"
require_relative "pass/pass_08_typed_constant_folder"
require_relative "pass/pass_09_lir_generator"
require_relative "pass/pass_11_realtime_context_checker"
require_relative "pass/pass_12_cpp_source_generator"

module BareRubyProt
  class Compiler
    # **What the first stage writes is not what was built.** The C++, the build system that
    # turns it into an artifact, and the manifest describing both are the boundary between
    # the two stages — real files on disk, handable to the second stage on their own — but
    # nobody asked for them. They live where the machinery lives, under the name of the
    # command that fills the directory.
    #
    # **Where a run writes is the run's, not this file's.** It was found from beside this
    # file, which was the same place while the compiler was a tree; a compiler that is a
    # gem would write its output into the installed gem instead. It is found from where
    # the command was run, which is the directory the sources were named from.
    COMPILE_DIRECTORY = File.expand_path(".bareruby/compile", Dir.pwd)
    STATUS_COMPILE_ERROR = 10
    BEGIN_ERROR = "error: begin requires the exception mechanism, which --no-exceptions removes."
    STDOUT_NOTICE = "notice: puts is not emitted in the freestanding build (stdout_channel = none). " \
                    "Enable a stdout channel to observe it."

    # Everything written last time goes, so what is left afterwards is exactly what this
    # run produced. It is done once for a command rather than once for a compilation,
    # because one command may compile more than once — targets that disagree about debug
    # cannot share a run — and the second must not erase the first.
    def self.clear_output = FileUtils.rm_rf(COMPILE_DIRECTORY)

    def initialize(source_file_name, targets:, debug:, exceptions:)
      @source_file_name = source_file_name
      @targets = targets
      @debug = debug
      @exceptions = exceptions
    end

    # **Each pass hands its result to the next one and nothing else happens in between.**
    # Every boundary here used to be written to disk in two forms and the next pass fed
    # from what was read back, which proved the representations survive a round trip — a
    # real property, and one worth an option that says which boundaries to write. It was
    # not that: it was every boundary, every run, whether or not anybody was looking. What
    # is left is the pipeline, and what to emit from it is a question asked from scratch.
    def run
      FileUtils.mkdir_p(COMPILE_DIRECTORY)

      generator = Pass::BareRubyAstGenerator.new(@source_file_name).run
      generator.notices.each { |notice| warn notice }
      result = generator.result

      result = pass_02(result)
      result = pass_03(result)

      reject_begin_without_exceptions(result)

      result = pass_05(result)
      result = pass_06(result)
      result = pass_07(result)
      result = pass_08(result)
      result = pass_09(result)
      result = pass_11(result)

      generator = pass_12(result)
      warn STDOUT_NOTICE if generator.stdout_notice

      write_artifacts(generator.result)

      0
    end

    def write_artifacts(artifacts)
      artifacts.each do |relative_path, content|
        path = File.join(COMPILE_DIRECTORY, relative_path)
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, content)
      end
    end

    def pass_01 = Pass::BareRubyAstGenerator.new(@source_file_name).run.result

    def pass_02(bareruby_ast) = Pass::Desugarer.new(bareruby_ast).run.result

    def pass_03(bareruby_ast) = Pass::LiteralFolder.new(bareruby_ast).run.result

    def pass_05(bareruby_ast) = Pass::TypeInferrer.new(bareruby_ast).run.result

    def pass_06(typed_ast) = Pass::BlockInliner.new(typed_ast).run.result

    def pass_07(typed_ast) = Pass::SymbolToIdConverter.new(typed_ast).run.result

    def pass_08(typed_ast) = Pass::TypedConstantFolder.new(typed_ast).run.result

    def pass_09(typed_ast) = Pass::LirGenerator.new(typed_ast).run.result

    def pass_11(low_ir) = Pass::RealtimeContextChecker.new(low_ir).run.result

    def pass_12(low_ir)
      Pass::CppSourceGenerator.new(low_ir, targets: @targets, debug: @debug, exceptions: @exceptions).run
    end

    # --no-exceptions removes the mechanism, so begin has nothing to land on and is
    # rejected outright rather than quietly doing nothing.
    def reject_begin_without_exceptions(bareruby_ast)
      return if @exceptions
      return unless Pass::TypeInferrer.new(bareruby_ast).contains_begin?(bareruby_ast.program_body)

      warn BEGIN_ERROR
      exit STATUS_COMPILE_ERROR
    end

  end
end
