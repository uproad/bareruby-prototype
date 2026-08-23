# frozen_string_literal: true

require_relative "arena_string"

module BareRubyProt
  # The printf one interpolation renders as: the static parts become the format, the rest
  # become its values, and the widths they can reach become the room a buffer needs. Every
  # one of the four forms that can ask — puts, a UART write, an assignment to a
  # fixed-capacity local, an arena string — wants some of these same three answers.
  class PrintfFormat
    # Widest rendering of each type, used to size the temporary buffer an interpolation
    # assigns into. A String of unknown capacity has no honest bound here; a real
    # implementation would carry the capacity in the type, so this is the one number in
    # the estimate that is a placeholder rather than a derivation.
    MAX_LENGTHS = { Int32: 11, Int64: 20, Bool: 5, Fixed: 12, String: 64 }.freeze

    # Bool and Fixed have no printf conversion of their own, so to_s is a real call.
    # Int64 has one on paper and not on the machines: the smallest printfs — newlib-nano,
    # avr-libc — read no ll length modifier, so it crosses as a string too.
    TO_S_FUNCTIONS = { Bool: :bareruby_bool_to_s, Fixed: :bareruby_fixed_to_s,
                       Int64: :bareruby_int64_to_s }.freeze

    def initialize(parts, typed_ast)
      @tast = typed_ast
      # nil renders as nothing, as it does in Ruby, and which parts are nil is settled
      # while compiling — so one leaves neither a conversion in the format nor a value
      # beside it.
      @parts = parts.reject { |part| typed_ast.node_type(part) == :nil }
    end

    def text
      @parts.map { |part| static?(part) ? escaped(part) : conversion_of(type_of(part)) }.join
    end

    def values = @parts.reject { |part| static?(part) }.map { |part| rendered(part) }

    # What the rendering can come to at its widest, plus the terminator. An interpolation
    # assigned to a fixed-capacity local has to bound every part while compiling; an arena
    # string is the way out of that estimate, because it measures the rendering instead.
    def capacity = @parts.sum { |part| length_of(part) } + 1

    private

    def static?(part) = @tast.node_type(part) == :string

    def type_of(part) = @tast.value_type(part)

    def escaped(part) = @tast.children_of(part)[0].gsub("%", "%%")

    def length_of(part)
      return @tast.children_of(part)[0].bytesize if static?(part)

      MAX_LENGTHS.fetch(type_of(part), 32)
    end

    def conversion_of(type)
      return "%s" if ArenaString.type?(type)

      # An integer crossing an ellipsis is not converted to a parameter's type, because
      # there is no parameter, so what arrives is whatever width the machine gave it. A
      # conversion therefore names a width rather than a language type: an Int32 is an
      # int on a 64-bit machine and a long on a 16-bit one, and long is 32 bits on both.
      # Pass 12 widens the value to match.
      case type
      when :String, :Bool, :Fixed, :Int64 then "%s"
      else "%ld"
      end
    end

    def rendered(part)
      return ArenaString.bytes_of(@tast, part) if ArenaString.type?(type_of(part))

      function = TO_S_FUNCTIONS[type_of(part)]
      return part unless function

      callee = @tast.create_callee(:builtin_function, nil, :to_s, function, [type_of(part)], :String)
      @tast.create_call(nil, callee, [part], nil, :String, @tast.span_of(part))
    end
  end
end
