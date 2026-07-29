# frozen_string_literal: true

module BareRubyProt
  # One method a class ended up with once every include was flattened into it, together
  # with the definitions it shadowed. The winner is depth 0 and each definition it hid
  # sits one deeper, which is what super walks and what keeps the generated function
  # names apart.
  #
  # What inference works out — the parameter types this call settled it at, the return
  # type, the typed body — is written back here, because a method is inferred once and
  # every later call reads the same answer.
  class MethodDefinition
    attr_reader :owner, :name, :parameters, :body, :ancestor, :depth
    attr_accessor :parameter_types, :return_type, :parameter_bindings, :typed_body

    # Every class has an initialize whether or not it defines one: Object's takes no
    # arguments and assigns nothing, so it is the floor super always reaches.
    def self.empty_initialize(owner)
      definition = new(owner, :initialize, [], [])
      definition.parameter_types = []
      definition.parameter_bindings = []
      definition.typed_body = []
      definition.return_type = :Nil
      definition
    end

    def initialize(owner, name, parameters, body, ancestor: nil)
      @owner = owner
      @name = name
      @parameters = parameters
      @body = body
      @ancestor = ancestor
      @depth = 0
    end

    def number_from(depth)
      @depth = depth
      ancestor&.number_from(depth + 1)
    end

    def chain = ancestor ? [self, *ancestor.chain] : [self]

    def inferred? = !return_type.nil?

    # A shadowed definition keeps its own name with its depth on the end, so super
    # reaches it and no two of them collide in the generated code.
    def qualified_name = depth.zero? ? name : :"#{name}__super#{depth}"
  end
end
