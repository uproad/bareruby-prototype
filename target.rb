# frozen_string_literal: true

require "yaml"

require_relative "isa"
require_relative "substrate"
require_relative "machine"
require_relative "binding/host/binding"
require_relative "binding/pico/binding"
require_relative "binding/stm32/binding"

module BareRubyProt
  # One machine the compiler produces artifacts for. The name is the whole identity of a
  # target: it is what the command line and target.yml spell, and it is the directory the
  # artifacts land in, so there is never a second vocabulary to translate between.
  #
  # Underneath the name a target is a composition of four answers, and they are kept apart
  # because none of them decides another:
  #
  #   isa       — the instruction set, named by its triple
  #   substrate — what lies underneath, which settles whether the program ends
  #   binding   — the API the generated code is written against, which owns the C++
  #   machine   — the instance and what can be reached on it
  #
  # One API serves boards that share no instruction set, one board is reachable through
  # more than one API, and an instruction set says nothing about whether an operating
  # system is underneath it. Naming the four separately is what keeps a machine whose
  # instruction set is WebAssembly, and a desktop whose peripherals are all stubs, from
  # each needing a kind of their own. Nothing is inferred here: a target that leaves an
  # answer out is a target nobody has decided about yet.
  class Target
    CONFIGURATION_FILE = File.expand_path("target.yml", __dir__)
    OPTION_PREFIX = "--target="
    DEFAULT_NAMES = ["host"].freeze

    attr_reader :name, :isa, :substrate, :binding, :machine

    def initialize(name, isa:, substrate:, binding:, machine:)
      @name = name
      @isa = isa
      @substrate = substrate
      @binding = binding
      @machine = machine
    end

    TABLE = {
      "host" =>
        new("host", isa: Isa::COMPILING, substrate: Substrate::HOSTED,
                    binding: HostBinding, machine: Machine::NONE),
      "raspberry-pi-pico" =>
        new("raspberry-pi-pico", isa: Isa::CORTEX_M0PLUS, substrate: Substrate::BARE_METAL,
                                 binding: PicoBinding, machine: Machine::PICO),
      "raspberry-pi-pico-w" =>
        new("raspberry-pi-pico-w", isa: Isa::CORTEX_M0PLUS, substrate: Substrate::BARE_METAL,
                                   binding: PicoBinding, machine: Machine::PICO_W),
      "raspberry-pi-pico2" =>
        new("raspberry-pi-pico2", isa: Isa::CORTEX_M33, substrate: Substrate::BARE_METAL,
                                  binding: PicoBinding, machine: Machine::PICO2),
      "raspberry-pi-pico2-w" =>
        new("raspberry-pi-pico2-w", isa: Isa::CORTEX_M33, substrate: Substrate::BARE_METAL,
                                    binding: PicoBinding, machine: Machine::PICO2_W),
      "stm32-nucleo-f446re" =>
        new("stm32-nucleo-f446re", isa: Isa::CORTEX_M4F, substrate: Substrate::BARE_METAL,
                                   binding: Stm32Binding, machine: Machine::NUCLEO_F446RE)
    }.freeze

    # The full names are what the artifacts are named after and what the documents say.
    # These are for typing at a prompt, and earn their place by being short.
    ALIASES = {
      "pico" => "raspberry-pi-pico",
      "picow" => "raspberry-pi-pico-w",
      "pico2" => "raspberry-pi-pico2",
      "pico2w" => "raspberry-pi-pico2-w",
      "f446" => "stm32-nucleo-f446re"
    }.freeze

    def self.[](name) = TABLE.fetch(ALIASES.fetch(name, name))

    # Naming even one target on the command line settles the question, so target.yml is
    # not consulted at all rather than merged into: a run asked for exactly what it says.
    def self.select(options)
      names = options.map { |option| option.delete_prefix(OPTION_PREFIX) }
      names = configured_names if names.empty?
      names = DEFAULT_NAMES if names.empty?
      names.map { |name| self[name] }.uniq
    end

    def self.configured_names
      YAML.safe_load_file(CONFIGURATION_FILE).dig("bareruby", "compile", "target") || []
    end
  end
end
