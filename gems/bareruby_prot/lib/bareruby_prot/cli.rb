# frozen_string_literal: true

require "English"
require "fileutils"

# The whole of what this side needs from the first stage: a compiler to run, and the
# vocabulary a composition is spelled in, which comes with it.
require "bareruby_prot/compiler"

require_relative "deployment"
require_relative "catalog"

module BareRubyProt
  # The one way in. The commands stack rather than duplicate: build compiles first and
  # then runs a toolchain over what it produced, deploy builds first and then writes what
  # it built onto the boards that take it. Each does its own work and then the next one's.
  #
  # compile is the only command that reads nothing but its own arguments. From build
  # onwards a command needs to know which desk it is standing at — which boards are here
  # and where the external projects live — and that is what target.yml answers.
  class Cli
    USAGE = <<~USAGE
      Usage: bareruby COMMAND [SOURCE.rb] [OPTIONS]

        compile SOURCE.rb   Ruby to C++, into build/<composition>/.
                            Reads no configuration; without --target the target is the
                            machine doing the compiling.
        build   SOURCE.rb   compile, then run each binding's toolchain over what it produced,
                            leaving the artifact beside its sources.
        flash               Write what build left onto the boards that take it.
        deploy  SOURCE.rb   build, then flash.
        target add          Ask which machine this is, and write the answer into
                            target.yml. Nothing in an entry has to be looked up.
        target list         Every machine that can be targeted, by family.

      Options:
        --target=NAME       Work on NAME, repeatable. Names and their short forms are in
                            `bareruby target list`. Without it, build takes its targets from
                            target.yml — see target.yml.sample.
        -d, --debug         Build the debug firmware, whatever target.yml says.
        --no-exceptions     Reject begin/rescue and leave the unwinder out.
    USAGE

    def self.run(arguments) = new(arguments).run

    def initialize(arguments)
      @arguments = arguments.dup
      @command = @arguments.shift
      @debug = [@arguments.delete("-d"), @arguments.delete("--debug")].any?
      @exceptions = @arguments.delete("--no-exceptions").nil?
      @target_options = @arguments.grep(/\A#{Target::OPTION_PREFIX}/)
      @arguments -= @target_options
    end

    def run
      case @command
      when "compile" then compile
      when "build" then build
      when "flash" then flash
      when "deploy" then deploy
      when "target" then target
      else usage
      end
    end

    def target
      case @arguments[0]
      when "add" then Catalog.add
      when "list" then Catalog.list
      else usage
      end
    end

    def compile
      Compiler.clear_output
      compile_for(Target.select(@target_options), debug: @debug)
    end

    # One entry at a time rather than one run for all of them, because two entries may
    # disagree about debug and that disagreement reaches the generated C++. Clearing the
    # output once and compiling into it repeatedly is what lets them differ.
    def build
      planned = entries
      return nothing if planned.empty?

      Compiler.clear_output
      done = planned.all? do |entry|
        compile_for([entry.target], debug: debug?(entry))
        place(entry)
        entry.target.binding.toolchain.run(directory_of(entry), options: entry.options)
      end
      done ? 0 : 1
    end

    # What is on the boards is whatever the last build left, so flashing on its own is
    # deliberate: it repeats a deployment without compiling it again.
    # A tool that refuses has already said why, so its refusal is passed to the shell as a
    # status rather than dressed up as an error of this program's own.
    def flash
      planned = entries
      return nothing if planned.empty?

      done = planned.all? do |entry|
        entry.target.binding.flash.run(directory_of(entry), boards: entry.boards,
                                                        options: entry.options)
      end
      done ? 0 : 1
    end

    # Asking for a deployment and being told nothing is worse than being told there is
    # none: an empty run looks exactly like a successful one. So it is said, and the
    # status says it too.
    def nothing
      warn "bareruby: nothing to #{@command}. Run `bareruby target add` to say which " \
           "boards are here, or name one with #{Target::OPTION_PREFIX}NAME."
      1
    end

    def deploy
      status = build
      return status unless status.zero?

      flash
    end

    # A record of this desk answers for the targets it names. Naming targets on the
    # command line instead asks for exactly those, and the record still answers for what
    # only it can know: which boards are attached, and where an external project lives.
    def entries
      recorded = Deployment.entries
      return recorded if @target_options.empty?

      Target.select(@target_options).map do |target|
        recorded.find { |entry| entry.target.equal?(target) } ||
          Deployment::Entry.new(target, nil, false, [], {})
      end
    end

    def debug?(entry) = @debug || entry.debug

    def directory_of(entry) = File.join(Compiler::BUILD_DIRECTORY, entry.directory)

    # An entry that named itself takes the name it chose, so that two entries built from
    # one composition — a debug one and a release one — do not land in one place.
    def place(entry)
      return unless entry.name

      FileUtils.rm_rf(directory_of(entry))
      FileUtils.mv(File.join(Compiler::BUILD_DIRECTORY, entry.target.directory),
                   directory_of(entry))
    end

    def compile_for(targets, debug:)
      Compiler.new(source, targets:, debug:, exceptions: @exceptions).run
    end

    # Named from where the command was run, like everything else a run reaches for. This
    # used to be beside the executable, which was the same place until the executable
    # became a gem.
    def source = @arguments[0] || File.expand_path("ref.rb", Dir.pwd)

    def usage
      warn USAGE
      2
    end
  end
end
