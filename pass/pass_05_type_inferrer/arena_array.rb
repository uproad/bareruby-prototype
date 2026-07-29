# frozen_string_literal: true

module BareRubyProt
  # An array a region hands out. It is the one array whose length the compiler does not
  # know: the length asked for is a run-time value, which is the whole reason the third
  # layer of the memory model exists. Its element type is left open and the first
  # assignment settles it, as `Array.new(n)` does.
  module ArenaArray
    def self.type(typed_ast, element = nil) = typed_ast.create_arena_array_type(element)

    def self.type?(type) = type.is_a?(Hash) && type[:kind] == :arena_array
  end
end
