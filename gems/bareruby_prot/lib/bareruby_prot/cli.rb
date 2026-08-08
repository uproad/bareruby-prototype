# frozen_string_literal: true

require "English"
require "fileutils"

# The whole of what this side needs from the first stage: a compiler to run, and the
# vocabulary a composition is spelled in, which comes with it.
require "bareruby_prot/compiler"

require_relative "deployment"
require_relative "catalog"
require_relative "progress"
require_relative "scaffold"
require_relative "toolchain"
require_relative "tools"

module BareRubyProt
  # The one way in. The commands stack rather than duplicate: build fetches what it will
  # build with and then compiles, and then runs a toolchain over what it produced; deploy
  # builds first and then writes what it built onto the boards that take it. Each does its
  # own work and then the next one's.
  #
  # **compile is the one that does not stack tools install**, because the first stage
  # reaches for no toolchain at all. A desk with not one SDK on it can still turn Ruby into
  # C++, and keeping that true is worth a command of its own.
  #
  # compile is the only command that reads nothing but its own arguments. From build
  # onwards a command needs to know which desk it is standing at — which boards are here
  # and where the external projects live — and that is what target.yml answers.
  class Cli
    USAGE = <<~USAGE
      Usage: bareruby COMMAND [SOURCE.rb] [OPTIONS]

        new NAME            Write a project that builds unedited. Uncomment a board in
                            its Gemfile to reach one.
        init FAMILY         Write FAMILY's config templates into this project, every
                            field explained in place. Renaming a .sample makes it real.
        compile SOURCE.rb   Ruby to C++, into .bareruby/compile/<composition>/. Makes no
                            artifact, so build/ stays empty. Reads no configuration; without
                            --target the target is the machine doing the compiling.
        build   SOURCE.rb   compile, then run each binding's toolchain over what it produced,
                            leaving the artifact — and only that — in build/<composition>/.
        flash               Write what build left onto the boards that take it.
        deploy  SOURCE.rb   build, then flash.
        target add          Ask which machine this is, and write the answer into
                            target.yml. Nothing in an entry has to be looked up.
        target list         Every machine that can be targeted, by family.
        tools install       Fetch what the recorded targets build with, pinned by version
                            and hash. build and flash do this first; silent once it is done.
        --version           Which versions of these gems are here.
        --help              This.

      Options:
        --target=NAME       Work on NAME, repeatable. An entry's name in target.yml, or a
                            composition — names and their short forms are in `bareruby
                            target list`. compile takes only the latter, reading no record.
                            Without it, build takes its targets from target.yml — see
                            target.yml.sample.
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

    # The table is finished here rather than by the command that drew it, because deploy is
    # two commands and one table: build starts it, flash goes on filling it in, and the
    # only place that knows both are over is the place they were both dispatched from.
    def run
      case @command
      when "--help", "-h", "help" then asked
      when "--version", "-v", "version" then version
      when "new" then @arguments.first ? Scaffold.run(@arguments) : usage
      when "init" then init
      when "compile" then compile
      when "build" then build
      when "flash" then flash
      when "deploy" then deploy
      when "target" then target
      when "tools" then tools
      else usage
      end
    ensure
      @progress&.finish
    end

    def target
      case @arguments[0]
      when "add" then Catalog.add
      when "list" then Catalog.list
      else usage
      end
    end

    # An SDK and a cross compiler are gigabytes of somebody else's release, and every board
    # needs one before anything can be built for it. Having its own verb is what lets CI
    # fetch them in a step it can cache, and lets a desk see what is about to be taken.
    def tools
      return usage unless @arguments[0] == "install"

      Tools.install(entries.map(&:target))
      0
    end

    # `bareruby init stm32`. What is written is the binding's to say — a family knows
    # what its projects keep in config/ and this side does not — so the command is
    # dispatch: find the family, find its binding, hand over. A binding with no init is
    # a family whose projects keep nothing, which is an answer rather than an error.
    def init
      family = Catalog.families.find { |one| one["key"] == @arguments[0] }
      return families_are unless family

      offered = Target[family["targets"].first].binding
      unless offered.respond_to?(:init)
        puts "bareruby: a #{family['key']} project keeps no configuration — nothing to write."
        return 0
      end
      offered.init.run
    end

    def families_are
      warn "bareruby: say which family to set up: " \
           "#{Catalog.families.map { |one| one['key'] }.join(', ')}"
      1
    end

    # **The one command a recorded name cannot reach**, because this is the command that
    # reads no record: a compilation is exactly what its command line asked for. So a name
    # only a desk knows is refused here rather than resolved, and refused the same way any
    # other unknown name is.
    #
    # **One compilation serves every target it was asked for**, because what differs
    # between them is decided in the last pass and everything before it is the same work.
    # So the row each target has in the table is filled in from that one run, and they all
    # say the same seconds — which is what happened.
    def compile
      wanted.each { |name| raise Stop, no_target(name, []) unless Target.named?(name) }
      Compiler.clear_output
      targets = Target.select(@target_options)
      showing(targets, %i[compile])
      @progress.at(:compile, targets) { compile_for(targets, debug: @debug) }
    end

    # One entry at a time rather than one run for all of them, because two entries may
    # disagree about debug and that disagreement reaches the generated C++. Clearing the
    # output once and compiling into it repeatedly is what lets them differ.
    def build
      planned = entries
      return nothing if planned.empty?

      showing(planned, %i[tools compile build])
      Compiler.clear_output
      planned.all? { |entry| built(entry) } ? 0 : 1
    end

    # The three stages one entry passes through, each timed where it happens. Fetching is
    # asked for one entry at a time rather than once for all of them so that the wait lands
    # on the row that waited; it is the same question asked repeatedly, and a binding whose
    # tools are already here answers it without reaching anywhere.
    def built(entry)
      @progress.at(:tools, [entry]) { Tools.install([entry.target]) }
      @progress.at(:compile, [entry]) do
        compile_for([entry.target], debug: debug?(entry))
        place(entry)
      end
      worked = @progress.at(:build, [entry]) do
        toolchain_of(entry).run(directory_of(entry), options: entry.options)
      end
      made(entry) if worked
      worked
    end

    # What is on the boards is whatever the last build left, so flashing on its own is
    # deliberate: it repeats a deployment without compiling it again.
    # A tool that refuses has already said why, so its refusal is passed to the shell as a
    # status rather than dressed up as an error of this program's own.
    def flash
      planned = entries
      return nothing if planned.empty?

      showing(planned, %i[tools flash])
      planned.all? { |entry| flashed(entry) } ? 0 : 1
    end

    def flashed(entry)
      @progress.at(:tools, [entry]) { Tools.install([entry.target]) }
      @progress.at(:flash, [entry]) do
        entry.target.binding.flash.run(directory_of(entry), boards: entry.boards,
                                                            options: entry.options)
      end
    end

    # Asking for a deployment and being told nothing is worse than being told there is
    # none: an empty run looks exactly like a successful one. So it is said, and the
    # status says it too.
    def nothing
      warn "bareruby: nothing to #{@command}. Run `bareruby target add` to say which " \
           "boards are here, or name one with #{Target::OPTION_PREFIX}NAME."
      1
    end

    # The table is asked for here, before build and flash are stacked underneath, so that
    # the two of them fill in one table with a column for every stage they pass through
    # rather than each drawing its own half of one.
    def deploy
      planned = entries
      return nothing if planned.empty?

      showing(planned, %i[tools compile build flash])
      status = build
      return status unless status.zero?

      flash
    end

    # **Whoever asks first says what the run is**, and everyone after gets what they asked
    # for. Which source is being compiled is worth saying only where something is compiled,
    # so the stages answer that too.
    def showing(rows, stages)
      @progress ||= Progress.new(@command, (shown if stages.include?(:compile)), rows, stages)
    end

    def shown = source.delete_prefix("#{Dir.pwd}/")

    # A record of this desk answers for the targets it names. Naming targets on the
    # command line instead asks for exactly those, and the record still answers for what
    # only it can know: which boards are attached, and where an external project lives.
    #
    # Read once, because deploy asks twice — and because the rows of the table are these
    # entries, so a second reading would be a second set of rows for one run.
    def entries = @entries ||= resolved

    def resolved
      recorded = Deployment.entries
      return recorded if @target_options.empty?

      wanted.map { |name| entry_named(name, recorded) }
    end

    def wanted
      @target_options.map { |option| option.delete_prefix(Target::OPTION_PREFIX) }
    end

    # **An entry's own name is looked for first, because it is the name in front of the
    # person typing.** It is what `build/` is named after and what the line saying where
    # the artifact went prints, so it is the name a next command is typed from. It is also
    # the only one that tells two entries of one composition apart — a debug build and a
    # release build of the same board are exactly that, which is what a record gives a
    # `name:` for. A composition still names itself, and answers with the first entry
    # spelling it, so `--target=pico` keeps meaning what it meant.
    def entry_named(name, recorded)
      recorded.find { |entry| entry.name == name } || composed(name, recorded)
    end

    # **A name that is neither is a refusal, not a stack.** It is a typo or a name from
    # another desk, which the person who typed it is the one who can fix, and both lists
    # it could have come from are short enough to hand back.
    def composed(name, recorded)
      raise Stop, no_target(name, recorded) unless Target.named?(name)

      target = Target[name]
      recorded.find { |entry| entry.target.equal?(target) } ||
        Deployment::Entry.new(target, nil, false, [], {})
    end

    def no_target(name, recorded)
      here = recorded.filter_map(&:name)
      recorded_names = here.empty? ? "" : "#{Deployment::FILE} records #{here.join(', ')}. "
      "no target is named #{name}. #{recorded_names}" \
        "`bareruby target list` prints every composition that can be named instead."
    end

    # **build/ holds what was built and nothing else.** The toolchains leave far more than
    # that behind — a cmake tree alone is 679 files and 9.4 MB against 52 KB of firmware —
    # and all of it is how the artifact was made rather than what was asked for. The binding
    # says which of what it left is the artifact; this side says where artifacts go.
    #
    # What was made is told to the table rather than printed, because it belongs to the row
    # that made it: every artifact is at build/<target>/, so the row already says all of the
    # path but the file name.
    def made(entry)
      made = toolchain_of(entry).artifact(directory_of(entry))
      kept = File.join(ARTIFACTS, entry.directory, File.basename(made))
      FileUtils.mkdir_p(File.dirname(kept))
      FileUtils.cp(made, kept)
      @progress.artifact(entry, kept.delete_prefix("#{Dir.pwd}/"))
    end

    ARTIFACTS = File.expand_path("build", Dir.pwd)

    # A binding with no toolchain is one whose second stage the manifest already describes
    # in full, which is an answer rather than something missing: what to run and what it
    # leaves behind are written down, and running them is this side's own work. A binding
    # names a toolchain when it has something to add around that.
    def toolchain_of(entry)
      found = entry.target.binding
      found.respond_to?(:toolchain) ? found.toolchain : Toolchain
    end

    def debug?(entry) = @debug || entry.debug

    def directory_of(entry) = File.join(Compiler::COMPILE_DIRECTORY, entry.directory)

    # An entry that named itself takes the name it chose, so that two entries built from
    # one composition — a debug one and a release one — do not land in one place.
    def place(entry)
      return unless entry.name

      FileUtils.rm_rf(directory_of(entry))
      FileUtils.mv(File.join(Compiler::COMPILE_DIRECTORY, entry.target.directory),
                   directory_of(entry))
    end

    def compile_for(targets, debug:)
      Compiler.new(source, targets:, debug:, exceptions: @exceptions).run
    end

    # Named from the project root, like everything else a run reaches for that it did not
    # bring with it. A project written by `new` keeps its program at app/main.rb; this
    # checkout is not one of those and keeps the representative program at its root, which
    # is what a run standing here compiles when it is given nothing.
    def source
      @arguments[0] || ["app/main.rb", "ref.rb"].map { |named| File.expand_path(named) }
                                                .find { |path| File.exist?(path) }
    end

    # **Being asked for the usage and getting it is not a misuse.** The text is the same
    # either way; where it goes and what the shell is told are not. Asked for, it is output
    # and the status is success; arrived at by typing something that is not a command, it
    # is a complaint and the status says so.
    def asked
      puts USAGE
      0
    end

    def usage
      warn USAGE
      2
    end

    # **What made an artifact is not one version.** The compiler lowers the program, but a
    # binding's C++ is compiled into it and a standard class brings its own declarations
    # and units, so the bytes on a board are decided by every one of these together — the
    # same reason a target is spelled out rather than named. So they are all listed.
    #
    # What is listed is what is installed. A checkout runs two of these gems out of its
    # working tree, and a working tree has no version to report; the copy named here is
    # then the installed one, which is not necessarily the code that just ran.
    def version
      Gem::Specification.select { |spec| spec.name.start_with?("bareruby_prot") }
                        .group_by(&:name).values
                        .map { |found| found.max_by(&:version) }
                        .sort_by(&:name)
                        .each { |spec| puts "#{spec.name} #{spec.version}" }
      0
    end
  end
end
