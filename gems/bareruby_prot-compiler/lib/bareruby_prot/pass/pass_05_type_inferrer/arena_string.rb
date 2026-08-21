# frozen_string_literal: true

require_relative "type_union"

module BareRubyProt
  # The string a program can grow, and the one value whose length is settled while running
  # rather than while compiling. A region hands one out; after that it answers for itself,
  # because the runtime owns the representation — the generated code reads no field of it,
  # and a string that has to grow finds its own region rather than being told one.
  #
  # Every binding names the one string, so appending through any of them is seen through
  # all of them, as Ruby does.
  module ArenaString
    NEW_FUNCTION = :bareruby_string_new
    FORMAT_FUNCTION = :bareruby_string_format
    APPEND_FORMAT_FUNCTION = :bareruby_string_append_format
    LENGTH_FUNCTION = :bareruby_string_length
    DUP_FUNCTION = :bareruby_string_dup
    BYTES_FUNCTION = :bareruby_string_bytes
    APPEND_BYTE_FUNCTION = :bareruby_string_append_byte

    OPERATOR_FUNCTIONS = {
      :<< => :bareruby_string_append,
      :+ => :bareruby_string_concat,
      :== => :bareruby_string_equal,
      :!= => :bareruby_string_equal
    }.freeze

    def self.type(typed_ast) = typed_ast.create_arena_string_type

    def self.type?(type) = type.is_a?(Hash) && type[:kind] == :arena_string

    # A variable-length string reaches everything that takes a static string — puts, a
    # UART, a format value, another string — through the bytes the region holds.
    def self.bytes_of(typed_ast, node)
      return node unless type?(typed_ast.value_type(node))

      callee = typed_ast.create_callee(
        :builtin_function, nil, :bytes, BYTES_FUNCTION, [typed_ast.value_type(node)], :String
      )
      typed_ast.create_call(nil, callee, [node], nil, :String, typed_ast.span_of(node))
    end

    # **`<<` takes a character code as well as a string**, as it does in Ruby, and appends
    # the one byte it names. The runtime has always had the call — it is how the receive
    # side built a string byte by byte — and nothing written in Ruby could reach it.
    def self.operator_function(name, source_type)
      return APPEND_BYTE_FUNCTION if name == :<< && TypeUnion::WIDTHS.include?(source_type)

      OPERATOR_FUNCTIONS.fetch(name) do
        raise "a variable-length string answers <<, +, ==, size, dup and to_s, not #{name}"
      end
    end
  end
end
