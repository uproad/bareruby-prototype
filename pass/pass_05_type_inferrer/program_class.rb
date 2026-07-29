# frozen_string_literal: true

module BareRubyProt
  # One class the program defines, after inheritance and include have been flattened into
  # it: the methods it ended up with, and the instance variables its methods assign.
  #
  # An instance starts with every field in its Nil state. Assignments guaranteed on every
  # path through initialize replace that state; every other field keeps the Nil path and
  # therefore has T? storage.
  class ProgramClass
    attr_reader :name

    def initialize(name, methods)
      @name = name
      @methods = methods
      @ivars = {}
      @initialized = []
    end

    def method_named(name) = @methods[name]

    # Every definition the class flattened, including the ones a subclass or a later
    # include shadowed, because super still reaches them.
    def definitions = @methods.values.flat_map(&:chain)

    def ivar?(name) = @ivars.key?(name)

    def ivar_type(name) = @ivars.fetch(name)

    def remember_ivar(name, type) = @ivars[name] = type

    def ivars = @ivars.map { |name, type| { name:, type: } }

    def initialized?(name) = @initialized.include?(name)

    def note_initialized(names) = @initialized |= names

    def nil_unless_initialized
      @ivars.each { |name, type| @ivars[name] = yield(type) unless initialized?(name) }
    end
  end
end
