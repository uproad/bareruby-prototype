# frozen_string_literal: true

require_relative "type_union"

module BareRubyProt
  # What is in scope where inference has reached: each local by name, with the binding it
  # refers to and the type it holds *here* — which is not always the type the binding was
  # declared with, because a test can tell us more than the declaration does. Self belongs
  # to it too: which class a method is being inferred against is part of what a name means.
  #
  # Paths get an environment each. A branch narrows its own copy, and the two are merged
  # back when they meet; a loop body does the same, except that a name it introduces may
  # never be assigned at all, so it comes back nilable.
  class TypeEnvironment
    attr_reader :self_class

    def initialize(typed_ast, self_class: nil, bindings: {})
      @tast = typed_ast
      @self_class = self_class
      @bindings = bindings
    end

    def fetch(name) = @bindings.fetch(name)

    def names = @bindings.keys

    def bind(name, binding, type) = @bindings[name] = [binding, type]

    # A path of its own, which narrowing and assignment may change without the others
    # seeing it.
    def branched = self.class.new(@tast, self_class: @self_class, bindings: @bindings.dup)

    def with(name, binding, type)
      self.class.new(@tast, self_class: @self_class, bindings: @bindings.merge(name => [binding, type]))
    end

    # An interrupt handler runs on its own, with none of the names around it.
    def without_locals = self.class.new(@tast, self_class: @self_class)

    # A test of a nilable local tells its path what the declaration cannot: on the true
    # side it is present, on the false side it is nil.
    def narrow(condition, truthy:)
      binding, type =
        case @tast.node_type(condition)
        when :reference
          @tast.children_of(condition)
        when :assignment
          assignment_binding, _value, assignment_type = @tast.children_of(condition)
          [assignment_binding, assignment_type]
        end
      return unless binding && binding[:kind] == :local && TypeUnion.nilable?(type)

      bind(binding[:name], binding, truthy ? type[:inner] : :Nil)
    end

    def merge_branch(left, right, left_reachable: true, right_reachable: true)
      return replace(left) unless right_reachable
      return replace(right) unless left_reachable

      (left.names | right.names).each do |name|
        left_entry = left.entry(name)
        right_entry = right.entry(name)
        binding = (left_entry || right_entry)[0]
        type = TypeUnion.of(@tast, left_entry ? left_entry[1] : :Nil, right_entry ? right_entry[1] : :Nil)
        binding[:type] = binding[:type] ? TypeUnion.of(@tast, binding[:type], type) : type
        bind(name, binding, type)
      end
    end

    # The body may execute zero times. Only names introduced by it need a new Nil path;
    # existing names retain the type known at loop exit, while their binding storage has
    # already absorbed any types assigned in the body.
    def merge_loop(body)
      (body.names - names).each do |name|
        binding, body_type = body.fetch(name)
        type = TypeUnion.of(@tast, :Nil, body_type)
        binding[:type] = binding[:type] ? TypeUnion.of(@tast, binding[:type], type) : type
        bind(name, binding, type)
      end
    end

    protected

    def entry(name) = @bindings[name]

    def replace(other) = @bindings.replace(other.bindings)

    def bindings = @bindings
  end
end
