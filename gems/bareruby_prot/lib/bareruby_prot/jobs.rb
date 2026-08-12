# frozen_string_literal: true

require "etc"

module BareRubyProt
  # One row's work, in a process of its own.
  #
  # **A deployment is mostly waiting for somebody else's build system, one target at a
  # time.** cmake is told to build and is given no `-j`, so a board's build occupies one
  # core of a desk that has many, and the next board does not start until it is done. Four
  # targets is four builds end to end for no reason but that a run only has one of itself.
  #
  # **Processes rather than threads**, for three reasons that all say the same thing: what
  # is shared should be nothing. The first stage is Ruby and Ruby runs one thread of it at
  # a time, so threads would leave compilation exactly as serial as it is now. The working
  # directory a second stage runs in belongs to a process, so two threads changing it are
  # two threads with one answer between them. And a run says things through `warn`, which
  # is a global — a child gets its own, which is the whole difference.
  #
  # **What the children do not get is the terminal.** It belongs to the parent, which is
  # drawing a table on it. A child says what it is doing on a pipe of its own and the
  # parent records it against the row it belongs to; the child's fd 2 is another pipe, so
  # everything it and everything it runs says arrives the same way, and is printed above
  # the table by the one process entitled to write there.
  module Jobs
    OPTION_PREFIX = "--jobs="
    BUFFER = 4096

    Child = Struct.new(:pid, :row, :events, :said)

    # **Every row is worked on, and the answer is whether all of them worked.** That is the
    # answer the serial form gave, so what changes here is when the work happens and not
    # what a caller can ask about it.
    def self.run(rows, limit:, progress:, &work)
      waiting = rows.dup
      running = []
      failed = false
      progress.ticking do
        until waiting.empty? && running.empty?
          running << start(waiting.shift, progress, &work) while running.size < limit && !waiting.empty?
          failed = true unless collect(running, progress)
        end
      end
      !failed
    end

    # A desk with more targets than cores would otherwise have them all waiting on each
    # other, and one with more cores than targets has nothing to give the extra ones.
    def self.limit(asked, rows)
      return [asked.to_i, 1].max if asked

      [rows.length, Etc.nprocessors].min
    end

    # **The child closes the reading ends and keeps the writing ones**, so that a pipe is
    # at end of file exactly when the process that could still write to it is gone. That
    # is how the parent knows a row is over without asking.
    def self.start(row, progress, &work)
      events = IO.pipe
      said = IO.pipe
      pid = fork do
        events.first.close
        said.first.close
        $stdout.reopen(said.last)
        $stderr.reopen(said.last)
        progress.reporting(events.last, row)
        exit(work.call(row) ? 0 : 1)
      end
      events.last.close
      said.last.close
      Child.new(pid, row, events.first, said.first)
    end

    # Whatever is readable, read, and whoever has nothing left to say is waited for. The
    # wait is what turns a finished process into an answer, and it happens here rather
    # than at the end so that a row that failed early is a row the table already says
    # failed.
    def self.collect(running, progress)
      readers = running.flat_map { |child| [child.events, child.said] }.reject(&:closed?)
      IO.select(readers).first.each { |reader| absorb(reader, running, progress) }
      done = running.reject { |child| [child.events, child.said].any? { |pipe| !pipe.closed? } }
      done.each { |child| running.delete(child) }
      done.all? { |child| Process.wait2(child.pid).last.success? }
    end

    def self.absorb(reader, running, progress)
      child = running.find { |one| one.events.equal?(reader) || one.said.equal?(reader) }
      lines(reader).each do |line|
        reader.equal?(child.events) ? progress.apply(line) : progress.said_by(child.row, line)
      end
    end

    # **Read what is there, and hold what is not yet a line.** A pipe hands over whatever
    # has arrived, which is a line and a half as often as it is a line, and asking it for
    # a line instead would be asking the reader to wait on a writer that is busy building.
    def self.lines(reader)
      buffered[reader] << reader.readpartial(BUFFER)
      complete(reader)
    rescue EOFError
      reader.close
      rest = buffered.delete(reader).to_s
      rest.empty? ? [] : [rest]
    end

    def self.complete(reader)
      found = []
      found << buffered[reader].slice!(/\A.*\n/).chomp while buffered[reader].include?("\n")
      found
    end

    def self.buffered = @buffered ||= Hash.new { |all, reader| all[reader] = +"" }
  end
end
