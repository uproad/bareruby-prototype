# frozen_string_literal: true

require_relative "method_definition"
require_relative "program_class"

module BareRubyProt
  # The classes and modules a program defines, and the one place inheritance and include
  # are resolved. Both are the same mechanism here — compile-time flat expansion — and
  # pass 2 has already turned a superclass into a leading include, so a class body is a
  # list of include calls followed by its own definitions.
  #
  # Later sources win over earlier ones and a class's own definitions win over all of
  # them. Every definition is copied into the class, which is what lets an included
  # method infer instance variables against the including class.
  class ProgramClasses
    def initialize(bareruby_ast)
      @brast = bareruby_ast
      @classes = {}
      @modules = {}
      @bodies = {}
      register_builtins
    end

    def register(statements)
      statements.each do |statement|
        @modules[member_name(statement)] = statement if @brast.module_definition?(statement)
        @bodies[member_name(statement)] = statement if @brast.class_definition?(statement)
      end
      statements.each { |statement| register_class(statement) if @brast.class_definition?(statement) }
    end

    def fetch(name) = @classes.fetch(name)

    def method_named(class_name, name) = fetch(class_name).method_named(name)

    private

    # BasicObject and Object are never written down. The compiler knows them, so a class
    # without its own initialize still has one and super always has a floor.
    def register_builtins
      @classes[:BasicObject] = ProgramClass.new(:BasicObject, {})
      @classes[:Object] = ProgramClass.new(:Object, { initialize: MethodDefinition.empty_initialize(:Object) })
    end

    def register_class(node)
      name, body = @brast.children_of(node)
      methods = { initialize: MethodDefinition.empty_initialize(name) }
      expand(body).each do |definition|
        method_name, parameters, method_body = @brast.children_of(definition)
        methods[method_name] =
          MethodDefinition.new(name, method_name, parameters, method_body, ancestor: methods[method_name])
      end
      methods.each_value { |definition| definition.number_from(0) }

      @classes[name] = ProgramClass.new(name, methods)
    end

    # The definitions a body contributes, ancestors first. A class source expands
    # transitively, so a chain of classes flattens in one pass.
    def expand(body)
      included_names(body).flat_map { |source| expand_source(source) } +
        body.select { |member| @brast.node_type(member) == :method_definition }
    end

    def expand_source(source)
      definition = @modules[source] || @bodies[source]
      definition ? expand(@brast.children_of(definition)[1]) : []
    end

    def included_names(body)
      body.select { |member| include_call?(member) }.map { |member| included_name(member) }
    end

    def include_call?(node)
      return false unless @brast.node_type(node) == :call

      receiver, call_name, = @brast.children_of(node)
      receiver.nil? && call_name == :include
    end

    def included_name(node) = @brast.children_of(@brast.children_of(node)[2].first)[1]

    def member_name(node) = @brast.children_of(node)[0]
  end
end
