# frozen_string_literal: true

require "yaml"

require "bareruby_prot/target/target"

require_relative "stop"

module BareRubyProt
  # What is true of this desk rather than of the project: which of the checked
  # compositions are wanted here, which boards are attached to take them, and the few
  # paths a build needs that only this desk knows. It is kept out of the repository for
  # that reason, so having no file at all is the ordinary case rather than a mistake.
  #
  # A composition is spelled out rather than named, because no one of the three answers
  # settles another: one machine is reachable through more than one binding, and one
  # machine whose chip carries two instruction sets is built for either of them. What the three
  # together name is looked up rather than assembled — a composition nobody has run is
  # not a target, it is an untried idea.
  class Deployment
    # **Under config/, from the project root.** Which compositions a project is built for
    # is configuration, so it sits where a project's configuration sits; the run is already
    # standing at the root by the time this is read (see Project), which is what makes a
    # plain relative name enough.
    #
    # It was found beside this file once, which was the same place until this file became
    # part of a gem — and a gem looking beside itself finds nothing and says the ordinary
    # thing, that this desk has recorded nothing, while quietly building somewhere other
    # than where it was told to.
    FILE = File.expand_path("config/target.yml", Dir.pwd)

    # A board takes the artifact its composition produced, and several identical boards
    # take the same one, so where to write it is a list and what to write is not.
    Entry = Struct.new(:target, :name, :debug, :boards, :options) do
      def directory = name || target.directory
    end

    def self.entries
      return [] unless File.exist?(FILE)

      recorded = YAML.safe_load_file(FILE)["targets"] || []
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
    FIELDS = %w[machine binding triple].freeze

    def self.target_of(record)
      wanted = FIELDS.to_h { |field| [field, record[field].to_s] }
      found = Target::TABLE.each_value.find { |target| spelling(target) == wanted }
      return found if found

      raise Stop, missing(wanted)
    end

    # **Two things are wrong in different places, and the advice differs.** A binding no
    # installed gem declares is a Gemfile that has not been edited or installed — the most
    # likely of the two by far, because commenting a line back out or cloning a project
    # without installing both do it. Sending that person to `target add` is sending them
    # somewhere that cannot help: the command offers what is installed, and this is not.
    #
    # A binding that exists but not in this combination is the other thing, and then the
    # compositions that do exist are what there is to say.
    def self.missing(wanted)
      unless bindings.include?(wanted["binding"])
        return "#{FILE} names binding: #{wanted['binding']}, and no installed gem " \
               "declares it. Uncomment its line in the Gemfile and run `bundle install`."
      end

      "#{FILE}: nothing is #{described(wanted)}. Run `bareruby target list`, or " \
        "`bareruby target add` to be asked instead.\n#{listed}"
    end

    def self.bindings = Target::TABLE.each_value.map { |target| target.binding.key.to_s }.uniq

    def self.spelling(target)
      { "machine" => target.machine.key.to_s, "binding" => target.binding.key.to_s,
        "triple" => target.isa.triple }
    end

    def self.described(wanted) = wanted.map { |field, value| "#{field}: #{value}" }.join(", ")

    def self.listed
      Target::TABLE.each_value.map { |target| "  #{described(spelling(target))}" }.join("\n")
    end
  end
end
