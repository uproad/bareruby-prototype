# frozen_string_literal: true

require "io/console"
require "stringio"

module BareRubyProt
  # What a run is doing, while it is doing it.
  #
  # A deployment is four programs deep — something fetched off the network, this compiler,
  # somebody else's build system, and a script that writes a chip — and every one of them
  # is quiet unless it fails. From outside that is one wait of unknown length, which is
  # indistinguishable from a hang: the first build of a board fetches a gigabyte and then
  # configures cmake, and until now it said nothing at all for minutes. So a run says which
  # stage each target is in and how long it has been there, in a table redrawn where it
  # stands.
  #
  # **How far along a stage is, is not asked.** cmake counts translation units, and the
  # link and the image that follow them are worth more than any of them, so a proportion
  # taken from that count reads 90% for as long as it reads anything. Elapsed time makes no
  # claim it cannot keep.
  #
  # **The terminal belongs to the table.** Everything else with something to say — a notice
  # from a pass, a build system that refused, the script naming the board it found — says
  # it above the table rather than into it, which is what keeps the table's height, and so
  # where it begins, something this side knows without having to look.
  #
  # A terminal is what all of that is for, so where there is none — a pipe, a log, CI —
  # there is no table and no redrawing. Each stage says one line as it finishes, which is
  # the same account in the form a file keeps.
  class Progress
    RUNNING = "+"
    PENDING = "."
    FAILED = "FAIL"
    SUCCESS = "success"
    FAILURE = "failed"
    COLUMN = 9
    COLUMNS = 80
    NAMES = 6
    TICK = 0.1
    KILOBYTE = 1024
    LABELS = { tools: "TOOLS", compile: "COMPILE", build: "BUILD", flash: "FLASH" }.freeze

    # The stages are given rather than fixed, because the verbs stack: what deploy does is
    # what build does and then what flash does, and a table that showed a column for a
    # stage the command does not reach would be a column of nothing.
    def initialize(command, source, rows, stages)
      @command = command
      @source = source
      @rows = rows
      @stages = stages
      @started = {}
      @spent = {}
      @failed = {}
      @artifacts = {}
      @out = $stdout
      @drawn = 0
      @begun = Time.now
      live? ? render : @out.puts(headline)
    end

    # A stage, timed while it happens. What the stage answers is handed back untouched, so
    # a caller reads exactly what it would have read without this; the one answer this side
    # reads is false, which is how every stage here refuses.
    #
    # **A stage already timed is not timed again.** deploy asks for the tools twice — once
    # as build, once as flash — and the second answer is instant because the first one
    # fetched them. Keeping the first is keeping the one that says what the wait was.
    def at(stage, rows)
      return yield if rows.all? { |row| @spent.key?([row, stage]) }

      rows.each { |row| @started[[row, stage]] = Time.now }
      answer = capturing { ticking { yield } }
      rows.each { |row| finished(row, stage, answer) }
      live? ? render : rows.each { |row| logged(row, stage) }
      answer
    end

    # Named by what it is rather than by where it is: every artifact is at build/<name>/,
    # and the row it sits on already says which name that is.
    def artifact(row, path)
      @artifacts[row] = [path, sized(File.size(path))]
      live? ? render : @out.puts("#{row.name.ljust(names)}-> #{path}  #{@artifacts[row].last}")
    end

    def finish
      @ended = true
      live? ? render : @out.puts(summary)
    end

    def finished(row, stage, answer)
      @spent[[row, stage]] = Time.now - @started[[row, stage]]
      @failed[[row, stage]] = true if answer == false
    end

    # Everything a run says while the table is up arrives here, because everything says it
    # through warn: a pass with a notice, a second stage handing back what the build system
    # printed, a flashing script naming the board it found. Said straight to the terminal it
    # would land in the middle of the table; collected, it is printed above it.
    def capturing
      said = StringIO.new
      $stderr = said
      yield
    ensure
      $stderr = STDERR
      note(said.string)
    end

    # The seconds have to move on their own — a number that only changes when a stage ends
    # says nothing during the stage, which is the whole of what there is to say while cmake
    # runs. Nothing else draws while this does: the stage's own words are collected until it
    # is over, and the thread is stopped before they are printed.
    def ticking
      @ticking = live?
      ticker = Thread.new { render while @ticking && sleep(TICK) } if @ticking
      yield
    ensure
      @ticking = false
      ticker&.join
    end

    def note(said)
      lines = said.lines(chomp: true).reject(&:empty?)
      return if lines.empty?

      erase
      lines.each { |line| @out.puts(line) }
      render if live?
    end

    def render
      erase
      @width = width
      lines = [headline, heading, *@rows.map { |row| line(row) }, summary]
      @out.print(lines.map { |one| "#{cut(one)}\n" }.join)
      @drawn = lines.length
    end

    # Up to where the table starts, and everything from there down goes. The count is this
    # side's own — it drew those lines and nothing else has written since.
    def erase
      @out.print("\e[#{@drawn}F\e[J") if @drawn.positive?
      @drawn = 0
    end

    # A line longer than the terminal is a line that wraps, and a wrapped line takes two
    # rows where the count says one, which puts every later redraw one row out.
    def cut(one) = one.length > @width ? one[0, @width] : one

    # A terminal that was never given a size answers with none, which is not the same as
    # answering that it is no columns wide.
    def width
      found = IO.console.winsize.last
      found.positive? ? found : COLUMNS
    end

    def headline
      "bareruby #{[@command, @source].compact.join(' ')} · " \
        "#{@rows.length} target#{'s' unless @rows.one?}"
    end

    def heading
      "#{'TARGET'.ljust(names)}#{@stages.map { |stage| LABELS[stage].rjust(COLUMN) }.join}" \
        "#{'  ARTIFACT' if artifacts?}"
    end

    def line(row)
      made = @artifacts[row]
      "#{row.name.ljust(names)}#{@stages.map { |stage| cell(row, stage).rjust(COLUMN) }.join}" \
        "#{"  #{File.basename(made.first)}  #{made.last}" if made}"
    end

    def cell(row, stage)
      return FAILED if @failed[[row, stage]]
      return seconds(@spent[[row, stage]]) if @spent.key?([row, stage])
      return "#{seconds(Time.now - @started[[row, stage]])}#{RUNNING}" if @started.key?([row, stage])

      PENDING
    end

    def logged(row, stage)
      said = @failed[[row, stage]] ? FAILED : "ok"
      @out.puts("#{row.name.ljust(names)}#{LABELS[stage].downcase.ljust(COLUMN)}" \
                "#{said.ljust(5)}#{seconds(@spent[[row, stage]])}")
    end

    # The last line is the one left on the screen when everything else has scrolled past,
    # so it is the one that says how it went. **Only once it is over**: a run still working
    # has not failed, and a verdict standing over stages that have yet to happen would be
    # saying it had.
    def summary
      "#{@command}: #{[verdict, "#{done}/#{@rows.length}", seconds(Time.now - @begun)].compact.join(' · ')}"
    end

    # Every target through every stage of what was asked for, or it did not do what was
    # asked. A run that stopped early answers the same way as one that was refused: the
    # stages it never reached are stages that did not happen.
    def verdict
      return unless @ended

      done == @rows.length ? SUCCESS : FAILURE
    end

    def done
      @rows.count do |row|
        @stages.all? { |stage| @spent.key?([row, stage]) && !@failed[[row, stage]] }
      end
    end

    def names = [*@rows.map { |row| row.name.length }, NAMES].max + 2

    def artifacts? = @stages.include?(:build)

    def seconds(spent) = format("%.1fs", spent)

    def sized(bytes)
      return format("%.1f MB", bytes.to_f / (KILOBYTE * KILOBYTE)) if bytes >= KILOBYTE * KILOBYTE

      format("%.1f KB", bytes.to_f / KILOBYTE)
    end

    # A table is drawn for someone watching it being drawn. A pipe is not that, and neither
    # is a terminal this run cannot ask the width of.
    def live? = @out.tty? && !IO.console.nil?
  end
end
