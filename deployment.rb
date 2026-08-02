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

    def self.target_of(record)
      machine = record["machine"].to_s
      api = record["api"].to_s
      triple = record["triple"].to_s
      found = Target::TABLE.each_value.find do |target|
        target.machine.key.to_s == machine && target.api.key.to_s == api &&
          target.isa.triple == triple
      end
      return found if found

      raise "#{FILE}: no target is #{machine} reached through #{api} built for #{triple}"
    end
  end
end
