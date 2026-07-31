# frozen_string_literal: true

require "yaml"

module BareRubyProt
  # One machine the compiler produces artifacts for. The name is the whole identity of a
  # target: it is what the command line and target.yml spell, and it is the directory the
  # artifacts land in, so there is never a second vocabulary to translate between.
  class Target
    CONFIGURATION_FILE = File.expand_path("target.yml", __dir__)
    OPTION_PREFIX = "--target="
    DEFAULT_NAMES = ["host"].freeze

    attr_reader :name, :board, :platform, :led, :backend

    # led is how the on-board LED is reached, which is a different question from which
    # chip the board carries: a wireless board puts its LED on the radio rather than on a
    # pin of the microcontroller, so two boards with one chip answer it differently.
    def initialize(name, board: nil, platform: nil, led:, backend: nil)
      @name = name
      @board = board
      @platform = platform
      @led = led
      @backend = backend || (board ? :pico : :host)
    end

    def hosted? = @backend == :host

    def pico? = @backend == :pico

    def stm32? = @backend == :stm32

    TABLE = {
      "host" => new("host", led: :host),
      "raspberry-pi-pico" =>
        new("raspberry-pi-pico", board: "pico", platform: "rp2040", led: :pin),
      "raspberry-pi-pico-w" =>
        new("raspberry-pi-pico-w", board: "pico_w", platform: "rp2040", led: :wireless),
      "raspberry-pi-pico2" =>
        new("raspberry-pi-pico2", board: "pico2", platform: "rp2350", led: :pin),
      "raspberry-pi-pico2-w" =>
        new("raspberry-pi-pico2-w", board: "pico2_w", platform: "rp2350", led: :wireless),
      "stm32-nucleo-f446re" =>
        new("stm32-nucleo-f446re", board: "NUCLEO-F446RE", platform: "stm32f4",
                                     led: :stm32, backend: :stm32)
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
