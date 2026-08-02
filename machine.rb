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
    attr_reader :name, :chip, :led

    # led is how the on-board LED is reached, which is a different question from which
    # chip the board carries: a wireless board puts its LED on the radio rather than on a
    # pin of the microcontroller, so two boards with one chip answer it differently.
    def initialize(name, chip: nil, led:)
      @name = name
      @chip = chip
      @led = led
    end

    # The machine doing the compiling has no peripheral to reach, so every binding call
    # lands on a stub. It is still a machine, and saying so keeps the hosted target from
    # being a shape of its own.
    NONE = new(nil, led: :host)

    PICO = new("pico", chip: "rp2040", led: :pin)
    PICO_W = new("pico_w", chip: "rp2040", led: :wireless)
    PICO2 = new("pico2", chip: "rp2350", led: :pin)
    PICO2_W = new("pico2_w", chip: "rp2350", led: :wireless)
    NUCLEO_F446RE = new("NUCLEO-F446RE", chip: "stm32f446", led: :stm32)
  end
end
