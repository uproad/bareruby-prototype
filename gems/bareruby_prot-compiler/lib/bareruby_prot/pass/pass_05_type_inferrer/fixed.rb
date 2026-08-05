# frozen_string_literal: true

module BareRubyProt
  # The fractional number this language has instead of a float: Q16.16, held in a plain
  # 32-bit integer. One whole unit is ONE steps, so a literal is scaled while compiling
  # and an integer that meets a Fixed is scaled to join it.
  #
  # Add and subtract act directly on that representation, which is why they are ordinary
  # machine operations. Multiply and divide are not: the intermediate is twice as wide,
  # and the rounding and the saturation that follow belong with it, so both go through
  # the runtime rather than being spelled in the generated code.
  module Fixed
    ONE = 65_536

    RUNTIME_OPERATORS = { :* => :bareruby_fixed_mul, :/ => :bareruby_fixed_div }.freeze

    CONVERSIONS = {
      to_fixed: { function: :bareruby_int32_to_fixed, return_type: :Fixed },
      to_i32: { function: :bareruby_fixed_to_i32, return_type: :Int32 }
    }.freeze

    def self.type?(type) = type == :Fixed

    # A float literal is the one place a fraction is written down, and it is settled here
    # rather than at run time.
    def self.scaled(value) = (value * ONE).round

    def self.conversion?(name) = CONVERSIONS.key?(name)

    def self.conversion(name) = CONVERSIONS.fetch(name)

    def self.runtime_operator?(operator) = RUNTIME_OPERATORS.key?(operator)

    # The same value as a Fixed. An integer literal is scaled where it stands; anything
    # else is scaled while running.
    def self.of(typed_ast, node)
      return node if type?(typed_ast.value_type(node))

      if typed_ast.node_type(node) == :integer
        return typed_ast.create_integer(typed_ast.children_of(node)[0] * ONE, :Fixed, typed_ast.span_of(node))
      end

      callee = typed_ast.create_callee(
        :builtin_function, nil, :to_fixed, CONVERSIONS.fetch(:to_fixed)[:function], %i[Int32], :Fixed
      )
      typed_ast.create_call(nil, callee, [node], nil, :Fixed, typed_ast.span_of(node))
    end

    def self.runtime_call(typed_ast, operator, receiver, arguments, span)
      callee = typed_ast.create_callee(
        :builtin_function, nil, operator, RUNTIME_OPERATORS.fetch(operator), %i[Fixed Fixed], :Fixed
      )
      typed_ast.create_call(nil, callee, [receiver] + arguments, nil, :Fixed, span)
    end
  end
end
