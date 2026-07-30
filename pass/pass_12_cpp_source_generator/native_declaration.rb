# frozen_string_literal: true

module BareRubyProt
  # How one class of the standard library is spelled in C: the struct an instance lives in
  # and the prototype of every function behind its methods.
  #
  # The names are not decided here — the class answers for those, so nothing is spelled
  # twice. What is decided here is how a declared type reads in C, which is the binding's
  # ABI rather than anything a program can see.
  class NativeDeclaration
    WIDTH = 96
    INDENT = "    "

    RETURN_TYPES = {
      Nil: "void", Int32: "int32_t", Int64: "int64_t", Bool: "bool", Fixed: "int32_t",
      "Arena::String": "bareruby_string_t *"
    }.freeze

    # A parameter of most types is one parameter in C. Two are not: a sequence of bytes
    # reaches the bus as a pointer and a count, and an interpolation reaches a variadic
    # function as its format and whatever it renders.
    PARAMETER_TYPES = {
      Int32: ["int32_t %s"], Int64: ["int64_t %s"], Bool: ["bool %s"], Fixed: ["int32_t %s"],
      String: ["const char *%s"], byte_sequence: ["const char *%s", "int32_t %s_length"],
      Interpolation: ["const char *%s", "..."]
    }.freeze

    ARENA_PARAMETER = "bareruby_arena_t *arena"
    BLOCK_PARAMETER = "bareruby_interrupt_handler_t handler"

    def initialize(standard_class)
      @standard_class = standard_class
    end

    def struct
      fields = @standard_class.instance_variables.map { |name, type| "#{INDENT}#{field(name, type)};" }
      (["typedef struct {"] + fields + ["} #{@standard_class.struct};"]).join("\n")
    end

    # One prototype per function, not per method. Two methods reach one function whenever a
    # rule cannot tell them apart — `read` and `read_voltage` are one reading, and `write`
    # and `puts` share the variadic one an interpolation goes to.
    def functions = prototypes.uniq { |function, _| function }.map { |_, text| text }

    # What one implementation of this class compiles to: whatever it needs above its
    # methods, then a definition for each. The signature is the same one the header
    # declares, so a definition and its prototype cannot drift apart.
    def definitions(variant)
      parts = variant.prelude ? [variant.prelude] : []
      parts + prototypes.uniq { |function, _| function }.filter_map do |function, prototype|
        method = method_of(function)
        next unless variant.body?(method)

        "#{prototype.delete_suffix(';')} {\n#{indented(variant.body(method))}}\n"
      end
    end

    private

    def indented(body) = body.lines.map { |line| line.strip.empty? ? line : "#{INDENT}#{line}" }.join

    def method_of(function)
      @standard_class.native_methods.find do |method|
        @standard_class.overloads_of(method).any? { |overload| overload.fetch(:function) == function }
      end
    end

    def field(name, type) = format(PARAMETER_TYPES.fetch(type).first, name)

    def prototypes
      @standard_class.native_methods.flat_map do |method|
        @standard_class.overloads_of(method).map do |overload|
          function = overload.fetch(:function)
          [function, signature(function, overload.fetch(:parameter_types),
                               overload.fetch(:return_type), method)]
        end
      end
    end

    # A method that answers with a variable-length string is handed the region to build it
    # in. Nothing declares that: the return type is what says a region is needed, and a
    # program can neither name one nor pass one.
    def signature(function, parameter_types, return_type, method)
      returned = RETURN_TYPES.fetch(return_type)
      parameters = [self_parameter]
      parameters << ARENA_PARAMETER if return_type == :"Arena::String"
      parameters.concat(named(parameter_types, method))
      parameters << BLOCK_PARAMETER if @standard_class.method_signature(method)[:block]
      wrapped("#{returned}#{returned.end_with?('*') ? '' : ' '}#{function}", parameters)
    end

    def self_parameter = "#{@standard_class.struct} *self"

    def named(parameter_types, method)
      required = @standard_class.parameter_names(method).zip(parameter_types)
      (required + @standard_class.keyword_parameters(method)).flat_map do |name, type|
        PARAMETER_TYPES.fetch(type).map { |shape| format(shape, name) }
      end
    end

    # A prototype is one line when it fits and packed into indented lines when it does not,
    # which is what the rest of the emitted C++ does.
    def wrapped(head, parameters)
      one_line = "#{head}(#{parameters.join(', ')});"
      return one_line if one_line.length <= WIDTH

      lines = parameters.each_with_object([]) do |parameter, packed|
        candidate = packed.empty? ? nil : "#{packed.last}, #{parameter}"
        if candidate && "#{INDENT}#{candidate},".length <= WIDTH then packed[-1] = candidate
        else packed << parameter
        end
      end
      "#{head}(\n#{lines.map { |line| "#{INDENT}#{line}" }.join(",\n")});"
    end
  end
end
