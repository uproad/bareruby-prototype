# frozen_string_literal: true

# What the visualizer runs. It builds a program for the hosted entry, interprets what the
# build left, and writes one line of JSON every time the program waits — which is every
# time the machine can have changed.
#
#     bundle exec ruby /path/to/vscode/watch.rb app/main.rb [SECONDS] [INPUT]
#
# **It runs in a project rather than in a checkout.** The working directory is whichever
# project is being watched, its `config/target.yml` is the record that is read, and its
# bundle is where the gems come from — which is why this is started through `bundle exec`
# and reaches the command as `bundle exec bareruby` rather than by a path. Nothing here
# knows where this file itself is.
#
# **It is told what to do while it runs.** A line of JSON on stdin says to play, to hold,
# to take one step, or how fast to play — so the display drives the run rather than
# waiting for it to be over. Virtual time is what a wait costs; playing is sleeping for
# as much real time as that wait was worth, divided by the speed.

require "json"
require "stringio"
require "yaml"

begin
  require "bareruby_prot/simulator"
rescue LoadError
  warn("watch: this project's bundle has no simulator in it.")
  warn('       Add it once:  gem "bareruby_prot-simulator"')
  exit(1)
end

RECORD = "config/target.yml"

# How long to sleep between reads of stdin while the run is held. Short enough that a
# button does not feel stuck, long enough that holding costs nothing.
IDLE = 0.02

# Which entry the hosted build is recorded under. **The binding is what identifies it** —
# it reaches one machine and one only — while `--target=` takes the entry's name, and what
# a desk calls its own machine is its own business.
def hosted
  entries = YAML.safe_load_file(RECORD)["targets"] || []
  found = entries.find { |entry| entry["binding"] == "host" }
  abort("watch: #{RECORD} records no entry whose binding is host.") unless found

  found["name"]
end

def built(name, source)
  system("bundle", "exec", "bareruby", "build", "--target=#{name}", source,
         out: File::NULL, err: File::NULL) || abort("watch: #{source} did not build.")
  File.join("build", name, "bareruby_program")
end

# The run, and what the display has told it to do with itself. A wait is where both
# happen: the orders are read, the clock is paid, and the frame goes out.
class Watching
  def initialize(said)
    @said = said
    @live = true
    @steps = 0
    @speed = 1.0
    @paid = 0
  end

  def at_wait(machine)
    orders
    hold(machine) unless @live
    play(machine) if @live
    frame(machine)
  end

  private

  # Held: nothing moves until a step is asked for, or until playing resumes.
  def hold(machine)
    until @live || @steps.positive?
      sleep(IDLE)
      orders
    end
    @steps -= 1 if @steps.positive?
    @paid = machine.clock.microseconds
  end

  # Playing: a wait that cost 500 virtual milliseconds costs half a second of somebody's
  # attention at 1.0, a twentieth of one at 10.0.
  def play(machine)
    owed = machine.clock.microseconds - @paid
    @paid = machine.clock.microseconds
    sleep(owed / 1_000_000.0 / @speed) if owed.positive?
  end

  # Whatever the display has said since last time. Reading without blocking is what keeps
  # a run that nobody is steering from stopping to listen.
  def orders
    loop do
      line = $stdin.read_nonblock(4096, exception: false)
      return if line == :wait_readable || line.nil?

      line.each_line { |order| obey(JSON.parse(order)) }
    end
  end

  def obey(order)
    @live = order["live"] if order.key?("live")
    @steps += order["step"] if order.key?("step")
    @speed = order["speed"].to_f if order.key?("speed")
  end

  def frame(machine, over: false)
    state = machine.snapshot
    state[:said] = printable(@said.string)
    state[:live] = @live
    state[:speed] = @speed
    state[:over] = over
    puts JSON.generate(state)
    $stdout.flush
  end

  public

  def finished(machine) = frame(machine, over: true)

  def printable(bytes)
    bytes.b.gsub(/[^\x20-\x7e\n]/) { |byte| format("\\x%02x", byte.ord) }
  end
end

def watched(artifact, seconds, input)
  said = StringIO.new(+"".b, "wb")
  watching = Watching.new(said)
  receiving(input) do |wire|
    run = BareRubyProt::Simulator::Run.new(artifact, seconds: seconds, out: said, input: wire)
    run.start { |machine| watching.at_wait(machine) }
    watching.finished(run.machine)
  end
end

# What the ports receive on. A file named on the command line is the same wire `emulate`
# is fed through; with nothing named, nothing arrives.
def receiving(input)
  return yield(nil) unless input

  File.open(input, "rb") { |file| yield(file) }
end

source = ARGV[0] || "app/main.rb"
seconds = Integer(ARGV[1] || 3)
watched(built(hosted, source), seconds, ARGV[2])
