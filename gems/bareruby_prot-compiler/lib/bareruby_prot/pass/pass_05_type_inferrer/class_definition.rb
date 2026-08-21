# frozen_string_literal: true

require_relative "method_definition"

module BareRubyProt
  # One class the program defines, after inheritance and include have been flattened into
  # it: the methods it ended up with, and the instance variables its methods assign.
  #
  # An instance starts with every field in its Nil state. Assignments guaranteed on every
  # path through initialize replace that state; every other field keeps the Nil path and
  # therefore has T? storage.
  class ClassDefinition
    # Every class the program declares, by name, with its includes flattened. Inheritance
    # and include are the same mechanism — pass 2 has already turned a superclass into a
    # leading include — so a class body is a list of include calls followed by its own
    # definitions. Later sources win over earlier ones and a class's own definitions win
    # over all of them. Every definition is copied in, which is what lets an included
    # method infer instance variables against the including class.
    #
    # A class has to be able to reach the bodies of the classes and modules it includes,
    # so they are all collected before any of them is flattened.
    #
    # **A name written twice is one class, opened twice**, as it is in Ruby: the bodies
    # join in the order they were written and a later definition of a method replaces an
    # earlier one. That is what lets a peripheral arrive with Ruby of its own and a
    # program still add to the same class.
    def self.declared_in(statements, bareruby_ast)
      sources = Hash.new { |hash, name| hash[name] = [] }
      statements.each do |statement|
        next unless bareruby_ast.module_definition?(statement) || bareruby_ast.class_definition?(statement)

        name, body = bareruby_ast.children_of(statement)
        sources[name] << body
      end

      classes = builtins
      statements.each do |statement|
        next unless bareruby_ast.class_definition?(statement)

        name, = bareruby_ast.children_of(statement)
        classes[name] = flattened(name, bareruby_ast, sources)
      end
      classes
    end

    # BasicObject and Object are never written down. The compiler knows them, so a class
    # without its own initialize still has one and super always has a floor.
    def self.builtins
      {
        BasicObject: new(:BasicObject, {}),
        Object: new(:Object, { initialize: MethodDefinition.empty_initialize(:Object) })
      }
    end

    def self.flattened(name, bareruby_ast, sources)
      methods = { initialize: MethodDefinition.empty_initialize(name) }
      sources[name].each do |body|
        included(body, bareruby_ast, sources).each do |member|
          method_name, parameters, method_body = bareruby_ast.children_of(member)
          methods[method_name] =
            MethodDefinition.new(name, method_name, parameters, method_body, ancestor: methods[method_name])
        end
      end
      methods.each_value { |definition| definition.number_from(0) }

      new(name, methods)
    end

    # The definitions a body contributes, ancestors first. A source expands transitively,
    # so a chain of classes flattens in one pass.
    def self.included(body, bareruby_ast, sources)
      names = body.select { |member| include_call?(member, bareruby_ast) }
                  .map { |member| included_name(member, bareruby_ast) }
      names.flat_map { |source|
        sources[source].flat_map { |opened| included(opened, bareruby_ast, sources) }
      } + body.select { |member| bareruby_ast.node_type(member) == :method_definition }
    end

    def self.include_call?(node, bareruby_ast)
      return false unless bareruby_ast.node_type(node) == :call

      receiver, call_name, = bareruby_ast.children_of(node)
      receiver.nil? && call_name == :include
    end

    def self.included_name(node, bareruby_ast)
      bareruby_ast.children_of(bareruby_ast.children_of(node)[2].first)[1]
    end

    private_class_method :builtins, :flattened, :included, :include_call?, :included_name

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
