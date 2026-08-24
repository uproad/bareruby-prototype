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
# The extension reads the lines it writes. Nothing about them is specific to an editor:
# running this in a terminal shows what the display is showing.

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

source = ARGV[0] || "app/main.rb"
seconds = Integer(ARGV[1] || 3)
watched(built(hosted, source), seconds, ARGV[2])
