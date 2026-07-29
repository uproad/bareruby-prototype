# frozen_string_literal: true

module BareRubyProt
  # A region: the third layer of the memory model. Its storage is reserved while
  # compiling, allocation from it bumps a pointer, and a block's region is released on the
  # way out of that block — so what it hands out may be held only by names the block
  # itself introduced. That is why a region has to remember what was already there when it
  # was entered. Blocks nest, and each region knows the one it is inside.
  #
  # An instance is a block whose body is being inferred right now. The long-lived form,
  # `Arena.new(size:)`, is an expression rather than a block and enters nothing.
  class Arena
    STRUCT = :bareruby_arena_t
    RESET_FUNCTION = :bareruby_arena_reset
    METHODS = %i[array string reset].freeze

    def self.type(typed_ast) = typed_ast.create_instance_type(:Arena, STRUCT)

    def self.type?(type) = type.is_a?(Hash) && type[:class_name] == :Arena

    attr_reader :binding, :enclosing

    def initialize(binding, enclosing:, outer_names:)
      @binding = binding
      @enclosing = enclosing
      @outer_names = outer_names
    end

    # A local the block did not introduce is still there once the region is released, and
    # so is every enclosing block's.
    def introduced?(name) = !@outer_names.include?(name)

    def outlived_by?(name)
      return true unless introduced?(name)

      enclosing ? enclosing.outlived_by?(name) : false
    end
  end
end
