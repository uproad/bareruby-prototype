# frozen_string_literal: true

module BareRubyProt
  # The instance the artifact runs on, and the few facts about it that the generated code
  # has to be told: which chip it carries, and how its on-board LED is reached. Everything
  # else a board decides — which pin, which peripheral instance, what the console is wired
  # to — is spelled by whichever binding reaches it, because the same board answers with
  # different names through different SDKs.
  #
  # A machine is not the same question as a binding: one board can be reached by more than
  # one of them, and one binding serves boards that share nothing but their SDK. The two
  # are named separately so that neither has to enumerate the other.
  class Machine
    # key is what a board is called wherever one has to be named — a deployment record,
    # the directory an artifact lands in — and it belongs to the board itself. name is
    # what one binding happens to call it, which is a different question: `pico_w` is the
    # word pico-sdk wants, and a second SDK reaching the same board would want another.
    attr_reader :key, :name, :chip, :led

    # led is how the on-board LED is reached, which is a different question from which
    # chip the board carries: a wireless board puts its LED on the radio rather than on a
    # pin of the microcontroller, so two boards with one chip answer it differently.
    def initialize(key, name: nil, chip: nil, led:)
      @key = key
      @name = name
      @chip = chip
      @led = led
    end

    # The machine doing the compiling has no peripheral to reach, so every binding call
    # lands on a stub. It is still a machine, and saying so keeps the hosted target from
    # being a shape of its own. The same answer serves a target that runs in a sandbox
    # rather than on a board.
    NONE = new(:none, led: :host)
  end
end

# One board to a file, so that adding a board is adding a file rather than editing a list
# every board already in the table has to be read past.
Dir.children(File.expand_path("machine", __dir__)).sort.each do |entry|
  require_relative "machine/#{entry}"
end
