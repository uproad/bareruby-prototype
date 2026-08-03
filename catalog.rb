# frozen_string_literal: true

require "yaml"

require_relative "deployment"

module BareRubyProt
  # Asking, rather than being told. A composition takes three answers and none of them is
  # a thing to be looked up, so what is asked for is the board — first roughly, by the
  # family its maker sells it in, then exactly — and the three follow from the answer.
  #
  # What to ask is data, in target-catalog.yml, so a board that does not exist yet is
  # reached by adding to that file rather than to this one.
  class Catalog
    FILE = File.expand_path("target-catalog.yml", __dir__)

    def self.families = YAML.safe_load_file(FILE).dig("bareruby", "families") || []

    def self.list
      Deployment::FIELDS.then do |fields|
        families.each do |family|
          puts family["label"]
          family["targets"].each do |name|
            spelling = Deployment.spelling(Target[name])
            puts "  #{name}"
            puts "    #{fields.map { |field| "#{field}: #{spelling[field]}" }.join('  ')}"
          end
          puts
        end
      end
      0
    end

    def self.add
      family = choose("Which board is it?", families) { |entry| entry["label"] }
      name = choose("Which one?", family["targets"]) { |entry| Target[entry].name }
      record = Deployment.spelling(Target[name])
      family["asks"].each { |ask| gather(record, answer(ask)) }
      write(record)
      0
    end

    # Two questions can answer into one heading — a project path and a configuration both
    # belong under options — so an answer joins what is there rather than replacing it.
    def self.gather(record, given)
      given.each do |key, value|
        record[key] = value.is_a?(Hash) ? (record[key] || {}).merge(value) : value
      end
      record
    end

    def self.choose(question, choices)
      puts
      puts question
      choices.each_with_index { |choice, index| puts "  #{index + 1}) #{yield(choice)}" }
      choices[read("1-#{choices.length}").to_i - 1] || choices.first
    end

    def self.answer(ask)
      puts
      puts ask["hint"] if ask["hint"]
      system(*ask["hint_command"].split, exception: false) if ask["hint_command"]
      given = ask["kind"] == "choice" ? pick(ask) : read_answer(ask)
      return {} if given.nil? || given == [] || given == ""

      place(ask["key"], given)
    end

    def self.read_answer(ask)
      puts ask["label"] + (ask["optional"] ? " (enter to skip)" : "")
      given = read(ask["kind"])
      case ask["kind"]
      when "boolean" then given.downcase.start_with?("y") || nil
      when "list" then given.split(/[,\s]+/).reject(&:empty?)
      else given
      end
    end

    def self.pick(ask)
      choose(ask["label"], ask["choices"]) { |choice| choice }
    end

    # A key with a dot in it is a key inside a key, which is how the answers only one
    # binding needs stay under that binding's own heading rather than spreading across it.
    def self.place(key, value)
      outer, inner = key.split(".")
      inner ? { outer => { inner => value } } : { outer => value }
    end

    def self.read(kind)
      print "#{kind}> "
      $stdin.gets.to_s.strip
    end

    # Appended as text rather than written back as YAML, so that whatever else is in the
    # file — the other entries, and whatever was said about them — survives being added to.
    def self.write(record)
      File.write(Deployment::FILE, "bareruby:\n  targets:\n") unless File.exist?(Deployment::FILE)
      File.open(Deployment::FILE, "a") { |file| file.write(rendered(record)) }
      puts
      puts "Added to #{Deployment::FILE}:"
      puts rendered(record)
    end

    def self.rendered(record)
      first, *rest = record.map { |key, value| lines(key, value) }.flatten
      ["    - #{first}", *rest.map { |line| "      #{line}" }].join("\n") + "\n"
    end

    def self.lines(key, value)
      case value
      when Array then ["#{key}:", *value.map { |item| "  - #{item}" }]
      when Hash then ["#{key}:", *value.map { |inner, item| "  #{inner}: #{item}" }]
      else ["#{key}: #{value}"]
      end
    end
  end
end
