# frozen_string_literal: true

module BareRubyProt
  # Who owns a value and who only points at one. Assignment shares an object or an array
  # as Ruby does, so most bindings hold an address; but an address has to lead somewhere,
  # and the binding a creation expression is assigned to is where that storage comes from.
  # That one holds the value itself and everything else points at it.
  #
  # For an instance variable the answer is settled by reading the class: a field assigned
  # a creation somewhere in it owns its storage and is embedded in the struct. For a local
  # it is settled as the function is lowered, which is why the scope of the moment answers.
  class BindingStorage
    attr_accessor :scope

    def initialize(low_ir, typed_ast, value_layout, methods)
      @lir = low_ir
      @tast = typed_ast
      @value_layout = value_layout
      @owning_ivars = owning_ivars(methods)
    end

    def creation?(node) = array_creation?(node) || arena_creation?(node) || object_creation?(node)

    def array_creation?(node) = %i[array array_fill array_dup].include?(@tast.node_type(node))

    def arena_creation?(node) = @tast.node_type(node) == :arena_new

    def object_creation?(node)
      @tast.node_type(node) == :call && %i[new binding_new].include?(@tast.children_of(node)[1][:kind])
    end

    def owns?(binding)
      return @owning_ivars.include?(binding[:name]) if binding[:kind] == :instance

      !scope.pointer?(binding[:name])
    end

    def type_of(binding, type)
      return @value_layout.type_of(type) unless @value_layout.shared?(type)

      owns?(binding) ? @value_layout.type_of(type) : @lir.pointer_type(@value_layout.type_of(type))
    end

    def ivar_type(ivar) = type_of({ kind: :instance, name: ivar[:name] }, ivar[:type])

    # A shared value in value position is its address.
    def rvalue(node, expression)
      return expression unless @value_layout.shared?(@tast.value_type(node))

      @lir.reference_to(expression)
    end

    # A local that owns storage is declared here rather than initialised from somewhere
    # else; an instance variable that owns storage is a field and is declared with the
    # struct.
    def declaration(binding, struct, value = nil)
      return [] unless binding[:kind] == :local && !scope.declared?(binding[:name])

      scope.declare(binding[:name])
      [@lir.create_declare(binding[:name], struct, value)]
    end

    # An object is declared with an empty initialiser, so a constructor that assigns only
    # some of the fields leaves the rest zeroed rather than undefined.
    def object_declaration(binding, struct)
      declaration(binding, struct, @lir.create_brace_init([], struct))
    end

    private

    def owning_ivars(methods)
      names = []
      each_assignment(methods) do |binding, value|
        names << binding[:name] if binding[:kind] == :instance && creation?(value)
      end
      names
    end

    def each_assignment(value, &block)
      return value.each { |element| each_assignment(element, &block) } if value.is_a?(Array)
      return unless value.is_a?(Hash) && value.key?(:children)

      yield(value[:children][0], value[:children][1]) if value[:type] == :assignment
      each_assignment(value[:children], &block)
    end
  end
end
