# frozen_string_literal: true

module BareRubyProt
  # A region: the third layer of the memory model. `arena` is a form rather than an object,
  # so there is nothing to name, pass or store — what a block hands out comes from whichever
  # region is current, and a method allocates without being told which. Storage is reserved
  # while compiling, allocation from it bumps a pointer, and leaving a block hands back
  # everything that block took. That is why a region has to remember what was already there
  # when it was entered. Blocks nest, and each region knows the one it is inside.
  #
  # An instance is a block whose body is being inferred right now.
  class Arena
    NAME = :Arena
    ARRAY_NAME = :Array
    STRING_NAME = :String

    # `Arena::Array` and `Arena::String` are the two values the first two layers cannot
    # hold. Nothing else lives under the name.
    def self.member?(owner, name)
      owner == NAME && [ARRAY_NAME, STRING_NAME].include?(name)
    end

    attr_reader :enclosing

    def initialize(enclosing:, outer_names:)
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
