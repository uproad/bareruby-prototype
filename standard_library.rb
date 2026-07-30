# frozen_string_literal: true

require "prism"

require_relative "standard_library/native_method"
require_relative "standard_library/standard_class"

module BareRubyProt
  # The classes the language offers, one file each under stdlib/.
  #
  # A file is read rather than run. Running it would settle the declarations by executing
  # Ruby, which puts the compiler's answer at the mercy of whatever the file does, and it
  # would turn a pure Ruby method body into a method of this compiler instead of source for
  # the passes. So the file is parsed, its top-level calls are read as declarations, and its
  # defs are read as methods.
  #
  # The files ship with the compiler and are found beside it. There is no search path, no
  # way to point the compiler somewhere else and no way to add to them, so what a given
  # source compiles to depends on the source alone. They are read in the order their names
  # sort in, so a run is the same run twice.
  class StandardLibrary
    DIRECTORY = File.expand_path("stdlib", __dir__)

    IVAR_DECLARATION = :native_ivar
    SIGNATURE_DECLARATION = :sig
    RETURN_KEY = :returns
    BLOCK_KEY = :block
    FUNCTION_KEY = :function

    def self.classes = @classes ||= new.read

    def self.[](name) = classes.fetch(name)

    def self.known?(name) = classes.key?(name)

    def read
      Dir.glob("*.rb", base: DIRECTORY).sort.to_h do |file_name|
        declared(Prism.parse_file(File.join(DIRECTORY, file_name)).value)
      end
    end

    private

    def declared(program)
      node = program.statements.body.first
      name = node.constant_path.name
      [name, read_class(name, node.body.body)]
    end

    def read_class(name, members)
      constants = {}
      instance_variables = {}
      methods = {}
      pending = []

      members.each do |member|
        case member
        when Prism::ConstantWriteNode then constants[member.name] = member.value.value
        when Prism::CallNode then read_declaration(member, instance_variables, pending)
        when Prism::DefNode
          methods[member.name] = read_method(member, pending) unless pending.empty?
          pending = []
        end
      end

      StandardClass.new(name, constants:, instance_variables:, methods:)
    end

    def read_declaration(node, instance_variables, pending)
      case node.name
      when IVAR_DECLARATION then instance_variables.merge!(keywords_of(node))
      when SIGNATURE_DECLARATION then pending << keywords_of(node)
      end
    end

    # The types come from the sig by name and the order comes from the def, so a parameter
    # list is assembled from both rather than taken from either.
    def read_method(node, signatures)
      parameters = node.parameters
      names = parameter_names(parameters)
      overloads = signatures.map do |signature|
        { parameter_types: names.map { |parameter| signature.fetch(parameter) },
          return_type: signature[RETURN_KEY], function: signature[FUNCTION_KEY] }
      end
      NativeMethod.new(
        node.name, overloads:, keywords: keyword_defaults(parameters),
                   block_context: signatures.first[BLOCK_KEY]
      )
    end

    # A rest parameter is one name in Ruby and a pair in C, and what it opens into is the
    # type's business, so it is read as the one parameter the def writes.
    def parameter_names(parameters)
      return [] if parameters.nil?

      names = parameters.requireds.map(&:name)
      parameters.rest ? names + [parameters.rest.name] : names
    end

    def keyword_defaults(parameters)
      return {} if parameters.nil?

      parameters.keywords.to_h { |keyword| [keyword.name, keyword.value.value] }
    end

    def keywords_of(node)
      node.arguments.arguments.first.elements.to_h do |element|
        [element.key.unescaped.to_sym, value_of(element.value)]
      end
    end

    def value_of(node)
      return node.unescaped.to_sym if node.is_a?(Prism::SymbolNode)

      node.value
    end
  end
end
