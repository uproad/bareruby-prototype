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

    attr_reader :name, :board, :platform

    def initialize(name, board: nil, platform: nil)
      @name = name
      @board = board
      @platform = platform
    end

    # A target with no board is built and run on the machine doing the compiling.
    def hosted? = @board.nil?

    TABLE = {
      "host" => new("host"),
      "raspberry-pi-pico" => new("raspberry-pi-pico", board: "pico", platform: "rp2040"),
      "raspberry-pi-pico2" => new("raspberry-pi-pico2", board: "pico2", platform: "rp2350")
    }.freeze

    # Naming even one target on the command line settles the question, so target.yml is
    # not consulted at all rather than merged into: a run asked for exactly what it says.
    def self.select(options)
      names = options.map { |option| option.delete_prefix(OPTION_PREFIX) }
      names = configured_names if names.empty?
      names = DEFAULT_NAMES if names.empty?
      names.uniq.map { |name| TABLE.fetch(name) }
    end

    def self.configured_names
      YAML.safe_load_file(CONFIGURATION_FILE).dig("bareruby", "compile", "target") || []
    end
  end
end
