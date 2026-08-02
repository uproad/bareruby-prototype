# frozen_string_literal: true

require "yaml"

require_relative "target/target"

module BareRubyProt
  # What is true of this desk rather than of the project: which of the checked
  # compositions are wanted here, which boards are attached to take them, and the few
  # paths a build needs that only this desk knows. It is kept out of the repository for
  # that reason, so having no file at all is the ordinary case rather than a mistake.
  #
  # A composition is spelled out rather than named, because no one of the three answers
  # settles another: one board is reachable through more than one API, and one board
  # whose chip carries two instruction sets is built for either of them. What the three
  # together name is looked up rather than assembled — a composition nobody has run is
  # not a target, it is an untried idea.
  class Deployment
    FILE = File.expand_path("target.yml", __dir__)

    # A board takes the artifact its composition produced, and several identical boards
    # take the same one, so where to write it is a list and what to write is not.
    Entry = Struct.new(:target, :name, :debug, :boards, :options) do
      def directory = name || target.directory
    end

    def self.entries
      return [] unless File.exist?(FILE)

      recorded = YAML.safe_load_file(FILE).dig("bareruby", "targets") || []
      recorded.map { |record| entry_of(record) }
    end

    def self.entry_of(record)
      Entry.new(
        target_of(record),
        record["name"],
        debug?(record["debug"]),
        Array(record["boards"]),
        record["options"] || {}
      )
    end

    # Written out, `true` and `1` are the two ways of saying so and everything else —
    # including saying nothing — is a release build.
    def self.debug?(value) = value == true || value == 1

    # All three, always. What an entry has to say does not depend on what it says, so a
    # record read here is the same shape as every other one, whatever it names. Writing
    # one by hand is not the way it is meant to be written — `bareruby target add` asks
    # and writes it — but a file written either way reads the same.
    FIELDS = %w[machine api triple].freeze

    def self.target_of(record)
      wanted = FIELDS.to_h { |field| [field, record[field].to_s] }
      found = Target::TABLE.each_value.find { |target| spelling(target) == wanted }
      return found if found

      raise "#{FILE}: nothing is #{described(wanted)}. Run `bareruby target list`, or " \
            "`bareruby target add` to be asked instead.\n#{listed}"
    end

    def self.spelling(target)
      { "machine" => target.machine.key.to_s, "api" => target.api.key.to_s,
        "triple" => target.isa.triple }
    end

    def self.described(wanted) = wanted.map { |field, value| "#{field}: #{value}" }.join(", ")

    def self.listed
      Target::TABLE.each_value.map { |target| "  #{described(spelling(target))}" }.join("\n")
    end
  end
end
