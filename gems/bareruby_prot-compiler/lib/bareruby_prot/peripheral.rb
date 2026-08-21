# frozen_string_literal: true

module BareRubyProt
  # One piece of hardware the language offers as a class: what it is called, the struct
  # the binding keeps its state in, the constants it publishes, and the binding functions
  # behind its constructor and its methods. Which implementation those functions have is
  # the second stage's business; what a program may say to them is settled here.
  #
  # **Not one of them is written here.** This file knows what a peripheral is made of and
  # knows no peripheral — every class arrives from a gem installed at the desk, by calling
  # `register`. What a program may say to hardware is settled by what is installed, and
  # this is the only door.
  class Peripheral
    attr_reader :name, :struct, :declaration, :library, :required_name

    def initialize(name, entry)
      @name = name
      @struct = entry[:struct]
      @constants = entry[:constants]
      @constructor = entry[:constructor]
      @methods = entry[:methods]
      @declaration = entry[:declaration]
      @library = entry[:library]
      @required_name = entry[:required_name]
      @units = entry[:units] || {}
      @variadic = entry[:variadic] || {}
    end

    # **Which translation unit a binding must supply, and how to tell it is needed.** The
    # peripheral names its own C functions, because they are its own; the binding says
    # what file answers a key, because the file is its own. Neither has to know the other
    # to agree, and a peripheral nobody installed asks for nothing.
    def units_reached(low_ir) = @units.select { |_key, functions| low_ir.calls?(*functions) }.keys

    def constant(name) = @constants.fetch(name)

    def constructor_function = @constructor[:function]

    def constructor_keywords = @constructor[:keywords] || {}

    def method_signature(name) = @methods.fetch(name)

    # **Whether this name is one of the C functions.** A peripheral is not only a mapping
    # onto them: the C is the smallest vocabulary that touches the hardware, and what sits
    # on top of it the class carries in Ruby. A name the mapping does not have is looked
    # for there, the same way it is for any other class.
    def mapped?(name) = @methods.key?(name)

    # **What a method does with a block, if it takes one.** The declaration form carries
    # one kind — `:realtime_handler`, whose block becomes an independent function running
    # in the realtime context — because one kind is what exists. A second arrives with the
    # second method that needs it, and not before: a shape drawn from one example is a
    # shape drawn again at the second. What the handler is handed, if anything, is the
    # declaration's to say too, as `block_parameter_types:` beside the kind.
    def block_of(name) = @methods.dig(name, :block)

    def variadic_from(name) = @variadic[name]

    def string_answers
      @methods.filter_map { |_name, one| one[:function] if one[:return_type] == :arena_string }
    end

    def instance_type(typed_ast) = typed_ast.create_instance_type(@name, @struct)

    ALL = {}

    # A peripheral arrives by saying what it is, from wherever it happens to live. The
    # compiler holds no list of them — what a program may say to hardware is settled by
    # what is installed, and this is the only door.
    def self.register(name, entry) = ALL[name] = new(name, entry)

    def self.[](name) = ALL.fetch(name)

    def self.known?(name) = ALL.key?(name)

    def self.all = ALL.values

    def self.declarations = all.filter_map(&:declaration)

    # **The Ruby a peripheral brings for the program.** It is a file the gem ships rather
    # than text written here, because it is Ruby a person edits and a program is compiled
    # from, not a string this side hands to the C++ compiler.
    def self.libraries = all.filter_map(&:library)

    def self.required_names = all.filter_map(&:required_name)

    def self.units_reached(low_ir) = all.flat_map { |one| one.units_reached(low_ir) }.uniq

    # The functions that answer a variable-length string. A declaration already says so in
    # its return type, so nothing has to be listed twice.
    def self.string_answers = all.flat_map(&:string_answers)

    def self.variadic_from(name) = all.filter_map { |one| one.variadic_from(name) }.first


    # Where a standard class declares itself. Nothing here says which ones exist — they
    # are found by looking rather than by naming, in every gem installed at the desk. The
    # ones this side still carries are above; the ones that have left are indistinguishable
    # from them once loaded.
    INSTALLED = "bareruby_prot/stdlib/*.rb"

    # **A class is found once even when it is reachable twice.** Looking in every gem means
    # looking in copies of one: a checkout that carries a gem in its working tree and has
    # the same gem installed sees both. Which class a declaration is for is the name it is
    # filed under, and the first one found wins — the load path is searched before the
    # installed gems, so a working tree beats a copy of itself. **A binding says the same
    # thing with the name of a directory**, because that is the shape it comes in; a class
    # comes as one file, so the file is what names it.
    #
    # Loading in name order after that is what keeps the compiler's answer the same
    # wherever the copies happened to be found.
    def self.installed = Gem.find_files(INSTALLED).uniq { |one| named(one) }.sort_by { |one| named(one) }

    def self.named(declaration) = File.basename(declaration, ".rb")

    def self.load_installed = installed.each { |one| require one }
  end
end

BareRubyProt::Peripheral.load_installed
