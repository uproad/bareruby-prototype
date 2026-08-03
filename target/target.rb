# frozen_string_literal: true

require_relative "isa"
require_relative "substrate"
require_relative "machine"
require_relative "api/host/binding"
require_relative "api/pico_sdk/binding"
require_relative "api/stm32cube/binding"
require_relative "api/arduino/binding"

module BareRubyProt
  # One machine the compiler produces artifacts for, and the roof over everything beside
  # this file: the instruction sets, the substrates, the machines and the APIs are all
  # here to be composed, and this is where the composing is done. The name is the whole
  # identity of a target — it is what the command line spells and the directory the
  # artifacts land in, so there is never a second vocabulary to translate between.
  #
  # Underneath the name a target is a composition of four answers, and they are kept apart
  # because none of them decides another:
  #
  #   isa       — the instruction set, named by its triple
  #   substrate — what lies underneath, which settles whether the program ends
  #   api       — what the generated code calls, and the binding that answers it in C++
  #   machine   — the instance and what can be reached on it
  #
  # One API serves boards that share no instruction set, one board is reachable through
  # more than one API, and an instruction set says nothing about whether an operating
  # system is underneath it. Naming the four separately is what keeps a machine whose
  # instruction set is WebAssembly, and a desktop whose peripherals are all stubs, from
  # each needing a kind of their own. Nothing is inferred here: a target that leaves an
  # answer out is a target nobody has decided about yet.
  class Target
    OPTION_PREFIX = "--target="
    DEFAULT_NAMES = ["host"].freeze

    attr_reader :name, :isa, :substrate, :api, :machine

    def initialize(name, isa:, substrate:, api:, machine:)
      @name = name
      @isa = isa
      @substrate = substrate
      @api = api
      @machine = machine
    end

    # Where the artifacts land. Three of the four answers are spelled out, because three
    # of them can differ while the rest agree: one board reached through two APIs, and one
    # board built for either of the two instruction sets its chip carries, are different
    # firmware that must not overwrite each other. The substrate is left out because the
    # triple already carries it. It is a long name, and that length is the information.
    def directory = "#{@machine.key}-#{@api.key}-#{@isa.triple}"

    TABLE = {
      "host" =>
        new("host", isa: Isa::COMPILING, substrate: Substrate::HOSTED,
                    api: HostBinding, machine: Machine::NONE),
      "raspberry-pi-pico" =>
        new("raspberry-pi-pico", isa: Isa::CORTEX_M0PLUS, substrate: Substrate::BARE_METAL,
                                 api: PicoSdkBinding, machine: Machine::PICO),
      "raspberry-pi-pico-w" =>
        new("raspberry-pi-pico-w", isa: Isa::CORTEX_M0PLUS, substrate: Substrate::BARE_METAL,
                                   api: PicoSdkBinding, machine: Machine::PICO_W),
      "raspberry-pi-pico2" =>
        new("raspberry-pi-pico2", isa: Isa::CORTEX_M33, substrate: Substrate::BARE_METAL,
                                  api: PicoSdkBinding, machine: Machine::PICO2),
      "raspberry-pi-pico2-w" =>
        new("raspberry-pi-pico2-w", isa: Isa::CORTEX_M33, substrate: Substrate::BARE_METAL,
                                    api: PicoSdkBinding, machine: Machine::PICO2_W),
      "stm32-nucleo-f446re" =>
        new("stm32-nucleo-f446re", isa: Isa::CORTEX_M4F, substrate: Substrate::BARE_METAL,
                                   api: Stm32CubeBinding, machine: Machine::NUCLEO_F446RE),
      "arduino-mega2560" =>
        new("arduino-mega2560", isa: Isa::AVR, substrate: Substrate::BARE_METAL,
                                api: ArduinoBinding, machine: Machine::MEGA2560)
    }.freeze

    # The full names are what the artifacts are named after and what the documents say.
    # These are for typing at a prompt, and earn their place by being short.
    ALIASES = {
      "pico" => "raspberry-pi-pico",
      "picow" => "raspberry-pi-pico-w",
      "pico2" => "raspberry-pi-pico2",
      "pico2w" => "raspberry-pi-pico2-w",
      "f446" => "stm32-nucleo-f446re",
      "mega" => "arduino-mega2560"
    }.freeze

    def self.[](name) = TABLE.fetch(ALIASES.fetch(name, name))

    # A run compiles exactly what it was asked for. Nothing is read from a file and
    # nothing is merged in behind the request, so what a command line says is the whole
    # of what happens; with nothing said, the machine doing the compiling is the target.
    def self.select(options)
      names = options.map { |option| option.delete_prefix(OPTION_PREFIX) }
      names = DEFAULT_NAMES if names.empty?
      names.map { |name| self[name] }.uniq
    end
  end
end
