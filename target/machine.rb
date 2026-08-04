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
    # the directory an artifact lands in — and it belongs to the board itself. chip is the
    # SoC it carries, which is a fact about the board rather than about any SDK.
    #
    # What one SDK calls this board is a different question and is not answered here:
    # `pico_w` is the word pico-sdk wants for the same board this calls `:pico_w`, and a
    # second SDK reaching it would want another. Those live in `binding/<binding>/machine/`.
    #
    # How a peripheral on this board is reached is not recorded here. It is not a fact
    # about the machine alone — the same indicator is `gpio_put` through one SDK and
    # `HAL_GPIO_WritePin` through another — so it lives in the cell where the machine and
    # the binding meet, under `binding/<binding>/machine/`.
    attr_reader :key, :chip

    def initialize(key, chip: nil)
      @key = key
      @chip = chip
    end

    # The machine doing the compiling has no peripheral to reach, so every binding call
    # lands on a stub. It is still a machine, and saying so keeps the hosted target from
    # being a shape of its own. The same answer serves a target that runs in a sandbox
    # rather than on a board.
    NONE = new(:none)
  end
end

# One board to a file, so that adding a board is adding a file rather than editing a list
# every board already in the table has to be read past.
Dir.children(File.expand_path("machine", __dir__)).sort.each do |entry|
  require_relative "machine/#{entry}"
end
