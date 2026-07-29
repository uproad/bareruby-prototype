# frozen_string_literal: true

module BareRubyProt
  # The type that admits both of two others, which is what a program asks for whenever two
  # paths meet: a branch and its missing else, a loop and the value before it, an instance
  # variable written twice. Nil ∪ T is T?, two integers are the wider of them, and two
  # arrays of a shape settle each other's element type.
  module TypeUnion
    WIDTHS = %i[Int8 Int16 Int32 Int64].freeze

    RANGES = {
      Int8: (-128..127),
      Int16: (-32_768..32_767),
      Int32: (-(2**31)..(2**31 - 1)),
      Int64: (-(2**63)..(2**63 - 1))
    }.freeze

    # An integer literal is as wide as it has to be, and never narrower than Int32.
    def self.literal(value) = widest(WIDTHS.find { |width| RANGES.fetch(width).cover?(value) }, :Int32)

    def self.widest(left, right) = WIDTHS[[WIDTHS.index(left), WIDTHS.index(right)].max]

    def self.of(typed_ast, left, right)
      return right if left == :NoReturn
      return left if right == :NoReturn
      return array_of(typed_ast, left, right) if same_array_shape?(left, right)
      return left if left == right
      return nilable_of(typed_ast, left, right) if left == :Nil || right == :Nil
      return joined_inner(typed_ast, left, right) if nilable?(left) || nilable?(right)

      widest(left, right)
    end

    def self.nilable?(type) = type.is_a?(Hash) && type[:kind] == :nilable

    def self.nilable_of(typed_ast, left, right)
      present = left == :Nil ? right : left
      return present if nilable?(present)

      typed_ast.create_nilable_type(present)
    end

    def self.joined_inner(typed_ast, left, right)
      typed_ast.create_nilable_type(of(typed_ast, inner_of(left), inner_of(right)))
    end

    def self.inner_of(type) = nilable?(type) ? type[:inner] : type

    # A missing element type means inference has not reached the first write yet; it is
    # not Nil. Propagate the known element type into both views of the same-shaped array.
    # Returning the newer view keeps later first-write inference connected to the binding
    # when both sides are still open here.
    def self.array_of(typed_ast, left, right)
      element =
        if left[:element].nil?
          right[:element]
        elsif right[:element].nil?
          left[:element]
        else
          of(typed_ast, left[:element], right[:element])
        end
      left[:element] = element
      right[:element] = element
      right
    end

    def self.same_array_shape?(left, right)
      return false unless left.is_a?(Hash) && right.is_a?(Hash)
      return true if left[:kind] == :arena_array && right[:kind] == :arena_array

      left[:kind] == :array && right[:kind] == :array && left[:capacity] == right[:capacity]
    end

    private_class_method :nilable_of, :joined_inner, :inner_of, :array_of, :same_array_shape?
  end
end
