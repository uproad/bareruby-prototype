# frozen_string_literal: true

module BareRubyProt
  # The borrowed string: a pointer and a length into bytes a binding owns. A realtime
  # handler cannot be handed an arena string — no region is current when it runs — so what
  # it receives is a view of the binding's buffer, valid for the block and no longer. It
  # answers == and != against a static string, and nothing else.
  #
  # The comparison deliberately lives outside the bareruby_string_ runtime family: linking
  # the string runtime is decided by that prefix, and a view must not pull the arena in.
  module StringView
    DECLARED_NAME = :StringView
    EQUAL_FUNCTION = :bareruby_text_view_equal

    def self.type(typed_ast) = typed_ast.create_string_view_type

    def self.type?(type) = type.is_a?(Hash) && type[:kind] == :string_view

    # The name a declaration writes for a handler's block parameter, mapped to the
    # language's type. Anything else is already a type the inferrer knows.
    def self.block_parameter_type(typed_ast, declared)
      declared == DECLARED_NAME ? type(typed_ast) : declared
    end
  end
end
