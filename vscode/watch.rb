# frozen_string_literal: true

# What the visualizer runs. It builds a program for the hosted entry, interprets what the
# build left, and writes one line of JSON every time the program waits — which is every
# time the machine can have changed.
#
#     ruby vscode/watch.rb samples/blink.rb [SECONDS] [INPUT]
#
# The extension reads those lines. Nothing about it is specific to an editor: the same
# lines are readable by anything, and running this in a terminal shows what the display
# is showing.
#
# **It is here rather than in the gem** because it is the extension's half — the gem
# answers with objects, and turning those into bytes for something that is not Ruby is
# the reader's own work.

require "json"
require "stringio"
require "yaml"

$LOAD_PATH.unshift(File.expand_path("../gems/bareruby_prot-simulator/lib", __dir__))
require "bareruby_prot/simulator"

RECORD = "config/target.yml"

# Which entry the hosted build is recorded under. `--target=` takes an entry's name, and
# this desk's name for its own machine is its own business.
def hosted
  entries = YAML.safe_load_file(RECORD)["targets"] || []
  found = entries.find { |entry| entry["machine"] == "host" }
  abort("watch: #{RECORD} records no entry whose machine is host.") unless found

  found["name"]
end

def built(name, source)
  system("./bareruby", "build", "--target=#{name}", source, out: File::NULL, err: File::NULL) ||
    abort("watch: #{source} did not build.")
  File.join("build", name, "bareruby_program")
end

# One line per wait, and one more when the run is over. Flushed each time, because a
# display that is waiting for a buffer to fill is showing the past.
def watched(artifact, seconds, input)
  said = StringIO.new(+"".b, "wb")
  receiving(input) do |wire|
    run = BareRubyProt::Simulator::Run.new(artifact, seconds: seconds, out: said, input: wire)
    run.start { |machine| frame(machine, said) }
    frame(run.machine, said, over: true)
  end
end

# What the ports receive on. A file named on the command line is the same wire `emulate`
# is fed through; with nothing named, nothing arrives.
def receiving(input)
  return yield(nil) unless input

  File.open(input, "rb") { |file| yield(file) }
end

def frame(machine, said, over: false)
  state = machine.snapshot
  state[:said] = said.string.b.gsub(/[^\x20-\x7e\n]/) { |byte| format("\\x%02x", byte.ord) }
  state[:over] = over
  puts JSON.generate(state)
  $stdout.flush
end

source = ARGV[0] || "samples/blink.rb"
seconds = Integer(ARGV[1] || 3)
watched(built(hosted, source), seconds, ARGV[2])
