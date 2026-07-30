# frozen_string_literal: true

module BareRubyProt
  # One class the language offers, as its declaration file says it: the constants it
  # publishes, the state an instance carries, and the signature of every method that has a
  # C++ body behind it. What a program may say to this class is settled here, and so is
  # every C name the class answers to — the names are derived from the Ruby ones, so no
  # declaration spells one twice.
  class StandardClass
    # CRuby's convention: self is the first argument of the C function, and the struct it
    # points at is named after the class.
    STRUCT_SUFFIX = "_t"
    FUNCTION_PREFIX = "bareruby_"

    # Ruby's constructor is `initialize`, and C has no constructors, so the function that
    # fills a fresh instance is named for what it does.
    CONSTRUCTOR_NAME = :initialize
    CONSTRUCTOR_SUFFIX = "init"

    attr_reader :name, :instance_variables

    def initialize(name, constants:, instance_variables:, methods:, variants:)
      @name = name
      @constants = constants
      @instance_variables = instance_variables
      @methods = methods
      @variants = variants
    end

    def variant(name) = @variants[name]

    def implemented? = !@variants.empty?

    def struct = :"#{FUNCTION_PREFIX}#{underscored}#{STRUCT_SUFFIX}"

    def constant(name) = @constants.fetch(name)

    def constructor_function = function_name(CONSTRUCTOR_NAME)

    def constructor_keywords = @methods.fetch(CONSTRUCTOR_NAME).keywords

    def constructor_parameter_types = @methods.fetch(CONSTRUCTOR_NAME).parameter_types

    def method?(name) = @methods.key?(name)

    # Declaration order, because it is the order the file reads in and nothing else would
    # be any more meaningful.
    def native_methods = @methods.keys

    def parameter_names(name) = @methods.fetch(name).parameter_names

    # A keyword becomes a trailing positional parameter of the C function, in declaration
    # order, which is what lets the caller default one without the binding knowing it did.
    def keyword_parameters(name) = @methods.fetch(name).keyword_types.to_a

    # Every function one method reaches, with the name each answers to settled. A method
    # reaches more than one when the type of an argument decides which.
    def overloads_of(name)
      method = @methods.fetch(name)
      method.overloads.map do |overload|
        overload.merge(function: overload[:function] || function_name(name))
      end
    end

    # The name a method answers to in C is derived unless the declaration says otherwise.
    # It says otherwise when two Ruby methods are one function, which no rule can produce.
    def method_signature(name)
      method = @methods.fetch(name)
      { function: method.function || function_name(name),
        printf_function: method.formatted? ? method.formatted_function : nil,
        parameter_types: method.parameter_types, return_type: method.return_type,
        block: method.block_context }
    end

    def instance_type(typed_ast) = typed_ast.create_instance_type(@name, struct)

    # `high?` asks a question in Ruby and returns a bool in C, so the mark that says so in
    # one language is dropped in the other rather than spelled some other way.
    def function_name(name)
      spelled = name == CONSTRUCTOR_NAME ? CONSTRUCTOR_SUFFIX : name.to_s.delete_suffix("?")
      :"#{FUNCTION_PREFIX}#{underscored}_#{spelled}"
    end

    private

    # OnboardLED becomes onboard_led: a run of capitals is one word, so the name reads the
    # way C spells it rather than one underscore per letter. A digit does not end a word
    # either, which is what keeps I2C from becoming i2_c.
    def underscored
      @name.to_s.gsub(/([A-Z]+)([A-Z][a-z])/, '\1_\2').gsub(/([a-z])([A-Z])/, '\1_\2').downcase
    end
  end
end
