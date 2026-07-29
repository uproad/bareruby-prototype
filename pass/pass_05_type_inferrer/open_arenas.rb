# frozen_string_literal: true

module BareRubyProt
  # The arena blocks being inferred right now, innermost last. A region is released when
  # its block is left, so what it handed out may not be stored anywhere that is still
  # there afterwards: each open block remembers the names that already existed when it
  # was entered, and those are exactly the ones that outlive it.
  class OpenArenas
    Region = Data.define(:binding, :outer_names)

    def initialize
      @regions = []
    end

    def open(binding, outer_names:)
      @regions.push(Region.new(binding:, outer_names:))
      yield
    ensure
      @regions.pop
    end

    # Where an allocation goes when the program does not say: the block it is written in.
    def innermost = @regions.last.binding

    def outlived_by?(name) = @regions.any? { |region| region.outer_names.include?(name) }
  end
end
