# frozen_string_literal: true

require "English"
require "fileutils"

# The whole of what this side needs from the first stage: a compiler to run, and the
# vocabulary a composition is spelled in, which comes with it.
require "bareruby_prot/compiler"

require_relative "deployment"
require_relative "catalog"
require_relative "jobs"
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
  # **What it is spared is fetching, not knowing where it stands.** compile reads target.yml
  # exactly as every other command does, because `--target=` naming one thing here and
  # another there is the kind of difference nobody can be told once: the same option, the
  # same file behind it, and a name that means the same in `compile` as in `deploy`.
  # Reading a record costs no SDK.
  class Cli
    USAGE = <<~USAGE
      Usage: bareruby COMMAND [SOURCE.rb] [OPTIONS]

        new NAME            Write a project that builds unedited. Uncomment a board in
                            its Gemfile to reach one.
        init FAMILY         Write FAMILY's config templates into this project, every
                            field explained in place. Renaming a .sample makes it real.
        compile SOURCE.rb   Ruby to C++, into .bareruby/compile/<target>/. Makes no
                            artifact, so build/ stays empty, and reaches for no toolchain.
        build   SOURCE.rb   compile, then run each binding's toolchain over what it produced,
                            leaving the artifact — and only that — in build/<target>/.
        flash               Write what build left onto the boards that take it.
        deploy  SOURCE.rb   build, then flash.
        target add          Ask which machine this is, and write the answer into
                            target.yml. Nothing in an entry has to be looked up.
        target attach       Put one board behind one entry, by writing the entry's name
                            into the board. It says that name over USB from then on, so
                            the desk finds it by name. Hold BOOTSEL on the board meant,
                            and say which entry with --target=NAME.
        target list         Every machine that can be targeted, by family.
        tools install       Fetch what the recorded targets build with, pinned by version
                            and hash. build and flash do this first; silent once it is done.
        --version           Which versions of these gems are here.
        --help              This.

      Options:
        --target=NAME       Work on NAME, repeatable. NAME is an entry's name in
                            target.yml, in every command that takes this. Without it, every
                            entry recorded there is worked on.
        -d, --debug         Build the debug firmware, whatever target.yml says.
        --no-exceptions     Reject begin/rescue and leave the unwinder out.
        --jobs=N            How many targets to build at once, each in a process of its
                            own. Without it, as many as there are targets, up to the
                            number of cores. Boards are found once, together, and then
                            written at the same time too.
    USAGE

    def self.run(arguments) = new(arguments).run

    def initialize(arguments)
      @arguments = arguments.dup
      @command = @arguments.shift
      @debug = [@arguments.delete("-d"), @arguments.delete("--debug")].any?
      @exceptions = @arguments.delete("--no-exceptions").nil?
      @target_options = @arguments.grep(/\A#{Target::OPTION_PREFIX}/)
      @arguments -= @target_options
      @jobs_options = @arguments.grep(/\A#{Jobs::OPTION_PREFIX}/)
      @arguments -= @jobs_options
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
      when "attach" then attach
      when "list" then Catalog.list
      else usage
      end
    end

    # `bareruby target attach --target=pico`. An entry says which machine and what it is
    # called; attaching puts one board behind it, by writing that name into the board so
    # that it says the name back. What that takes is entirely the binding's — where in a
    # board's flash a name goes, and how it gets there — so this is dispatch, as `init` is.
    # A binding whose boards carry no name of their own says so, which is an answer.
    #
    # **One entry, because one board is being named.** Every other command works on every
    # entry the record holds when none is named; this one cannot, because the name it would
    # write is the thing being chosen.
    def attach
      return one_target unless entries.one?

      entry = entries.first
      offered = entry.target.binding
      unless offered.respond_to?(:board)
        puts "bareruby: #{offered.key} boards carry no name of their own — nothing to attach."
        return 0
      end
      offered.board.attach(name: entry.name, target: entry.target,
                           directory: directory_of(entry)) ? 0 : 1
    end

    def one_target
      warn "bareruby: attach names one entry, because it puts a name on one board. " \
           "--target=NAME says which; #{Deployment::FILE} records " \
           "#{entries.map(&:name).join(', ')}."
      2
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

    # The first stage of what build does, stopping where the toolchain would start. It is
    # one entry at a time for build's reason: two entries may disagree about debug, and
    # that disagreement reaches the generated C++, so they cannot share a run.
    def compile
      planned = entries
      return nothing if planned.empty?

      showing(planned, %i[compile])
      Compiler.clear_output
      planned.each { |entry| compiled(entry) }
      0
    end

    def compiled(entry)
      @progress.at(:compile, [entry]) do
        compile_for([entry.target], debug: debug?(entry), into: root_of(entry))
      end
    end

    # What compile does, and then a toolchain over each of what it produced. The output is
    # cleared once for the command rather than once for each entry, which is what lets
    # entries that cannot share a compilation still share a directory to compile into.
    #
    # **Each target is worked on in a process of its own**, because from here down there is
    # nothing left that two of them share: what they build with is already fetched, and
    # each compiles into a root only it writes. What is left is a build system that uses
    # one core and is asked for one target at a time, which is a wait as long as all of
    # them added together for no reason but the shape of the run.
    def build
      planned = entries
      return nothing if planned.empty?

      showing(planned, %i[tools compile build])
      Compiler.clear_output
      fetched(planned)
      Jobs.run(planned, limit: limit(planned), progress: @progress) { |entry| built(entry) } ? 0 : 1
    end

    def limit(planned)
      Jobs.limit(@jobs_options.last&.delete_prefix(Jobs::OPTION_PREFIX), planned)
    end

    # **Everything the run will reach for, fetched once, before any of the work that
    # reaches for it.** The store is one directory on the desk and one SDK serves every
    # entry that names its binding, so asking entry by entry is asking the same question
    # repeatedly — and asking it from more than one place at a time is two runs unpacking
    # a gigabyte into the same name. One fetch, on one row of the table that spans them
    # all, is both the honest account of the wait and the thing that makes what follows
    # safe to do at once.
    def fetched(planned)
      @progress.at(:tools, planned) { Tools.install(planned.map(&:target)) }
    end

    # The two stages one entry passes through after what it builds with is already here,
    # each timed where it happens.
    def built(entry)
      compiled(entry)
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
    #
    # **Written at the same time, one process per target, as everything above it is.** The
    # two things that made this the one stage that could not be were both about a board
    # being found rather than about writing one: a bootloader volume went to the one place
    # the desk named for all of them, and a board was followed across its reset by
    # noticing which one appeared in BOOTSEL since a moment ago — the whole bus read to
    # answer a question about one board. A line in fstab per board answers the first, and
    # the port a board is plugged into answers the second. Neither leaves anything for two
    # runs to take from each other.
    #
    # **A board still takes its image one block at a time from one writer**, and the boards
    # of a single entry are still written in turn: the row is the unit of the table, and
    # several identical boards are one row.
    def flash
      planned = entries
      return nothing if planned.empty?

      showing(planned, %i[tools find flash])
      fetched(planned)
      found = found_boards(planned)
      Jobs.run(planned, limit: limit(planned), progress: @progress) { |entry| flashed(entry, found[entry]) } ? 0 : 1
    end

    # **Every board a run will write, put where it can be written from and then found —
    # once, for all of them, before any of them is written.** A board that is running has
    # to be rebooted into its bootloader first, and a bus with a board rebooting on it is
    # the one bus nobody can be identified on: devices come and go between two lines of a
    # scan, and a listing asked for at the wrong moment answers that nothing is there.
    # Asked once, after everything has settled, it answers about all of them at once.
    #
    # A binding with nothing to prepare has boards that are always where they are, which
    # is an answer rather than something missing.
    def found_boards(planned)
      @progress.at(:find, planned) do
        planned.group_by { |entry| entry.target.binding }.each_with_object({}) do |(binding, group), all|
          next unless binding.flash.respond_to?(:prepare)

          all.merge!(binding.flash.prepare(group.map { |entry| [entry, directory_of(entry)] }) || {})
        end
      end
    end

    def flashed(entry, found)
      @progress.at(:flash, [entry]) do
        entry.target.binding.flash.run(directory_of(entry), boards: entry.boards,
                                                            options: entry.options, found:)
      end
    end

    # Asking for a run and being told nothing is worse than being told there is none: an
    # empty run looks exactly like a successful one. So it is said, and the status says it
    # too.
    #
    # **There is nothing to name here.** A record with no entries in it leaves every name
    # wrong, so the way out is to write an entry rather than to type one.
    def nothing
      warn "bareruby: nothing to #{@command}. #{Deployment::FILE} records no target. " \
           "Run `bareruby target add` to say which machine is here."
      1
    end

    # The table is asked for here, before build and flash are stacked underneath, so that
    # the two of them fill in one table with a column for every stage they pass through
    # rather than each drawing its own half of one.
    def deploy
      planned = entries
      return nothing if planned.empty?

      showing(planned, %i[tools compile build find flash])
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

    # **An entry's own name is the only thing this names**, because it is the name in front
    # of the person typing: it is what `build/` is called, what the line saying where the
    # artifact went prints, and so the name a next command is typed from. It is also the
    # only one that tells two entries of one composition apart — a debug build and a
    # release build of the same board are exactly that.
    #
    # **Naming the composition instead used to work here, and that was the mistake.** Two
    # spellings for one thing meant `--target=pico` could reach an entry nobody had asked
    # for, meant the second entry of a composition could be built and not asked for, and
    # meant the same option answered to a different vocabulary in `compile`. One name, one
    # place it is written down.
    def entry_named(name, recorded)
      recorded.find { |entry| entry.name == name } || raise(Stop, no_target(name, recorded))
    end

    # **A name that is not in the record is a refusal, not a stack.** It is a typo or a
    # name from another desk, which the person who typed it is the one who can fix, and the
    # list it had to come from is short enough to hand back.
    #
    # Where to go next depends on which is wrong. A name that could have been meant is a
    # matter of spelling it as the record does; a machine that is not in there at all is a
    # matter of recording it, which is a question `target add` asks rather than an answer
    # anybody has to look up.
    def no_target(name, recorded)
      "no target is named #{name}. #{Deployment::FILE} records " \
        "#{recorded.map(&:name).join(', ')}. `bareruby target add` asks which machine is " \
        "here and writes another entry."
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
      kept = File.join(ARTIFACTS, entry.name, File.basename(made))
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

    # **An entry compiles into a root of its own, named after the entry.** The name is the
    # one word a person meets this entry by, so it is the one the machinery is filed
    # under — and it is also the only thing that tells two entries of one composition
    # apart, which a debug build and a release build of the same board are.
    #
    # **The root is the entry's, not the composition's**, because the runtime C++ sits at
    # the top of it. A root shared between entries would have those files written again by
    # every compilation into it, while some other entry was building from them. One root
    # each is what makes two entries able to be compiled at the same time.
    def root_of(entry) = File.join(Compiler::COMPILE_DIRECTORY, entry.name)

    # **The compiler names the directory after the composition, and this side lets it.**
    # It is inside the entry's root rather than beside it, so what a person navigates to
    # is still the name they wrote; the composition is spelled one level further in,
    # where the machinery is, and reaching the runtime from there is `..` exactly as the
    # manifests were written to expect.
    def directory_of(entry) = File.join(root_of(entry), entry.target.directory)

    def compile_for(targets, debug:, into:)
      Compiler.new(source, targets:, debug:, exceptions: @exceptions, into:).run
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
