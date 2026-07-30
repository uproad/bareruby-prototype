# frozen_string_literal: true

module BareRubyProt
  # One implementation of a class of the standard library: the C++ each of its methods is,
  # and whatever that C++ needs above them — an include, a static helper, a place to keep a
  # handler. Which implementation a build takes is the target's answer.
  #
  # The prelude belongs to the implementation rather than to the class, because what one
  # needs above its methods the other frequently does not.
  class NativeVariant
    attr_reader :name, :prelude

    def initialize(name, prelude:, bodies:)
      @name = name
      @prelude = prelude
      @bodies = bodies
    end

    def body(method) = @bodies.fetch(method)

    def body?(method) = @bodies.key?(method)
  end
end
