# frozen_string_literal: true

module BareRubyProt
  # One method with a C++ body behind it, as a sig and the def beneath it say it together.
  # The def gives the shape — the order of the parameters, which of them are keywords and
  # what they fall back to, whether a block is taken — and the sig gives the types. Neither
  # alone is the signature, which is why they are read as a pair.
  #
  # A method may carry more than one sig. What varies between them is the type of an
  # argument and the function that answers it, which is how one name in Ruby reaches
  # several functions in C.
  class NativeMethod
    INTERPOLATION = :Interpolation

    attr_reader :name, :keywords, :block_context

    def initialize(name, overloads:, keywords:, block_context:)
      @name = name
      @overloads = overloads
      @keywords = keywords
      @block_context = block_context
    end

    def block? = !@block_context.nil?

    def parameter_types = plain.fetch(:parameter_types)

    def return_type = plain.fetch(:return_type)

    def function = plain[:function]

    # The rendering an interpolation produces is measured while running, so the function
    # that takes one is variadic and stands apart from the one that takes text.
    def formatted? = !overload_taking(INTERPOLATION).nil?

    def formatted_function = overload_taking(INTERPOLATION)[:function]

    private

    def plain = @overloads.find { |overload| !overload[:parameter_types].include?(INTERPOLATION) }

    def overload_taking(type)
      @overloads.find { |overload| overload[:parameter_types].include?(type) }
    end
  end
end
