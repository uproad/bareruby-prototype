# frozen_string_literal: true

require_relative "isa"
require_relative "substrate"
require_relative "machine"

module BareRubyProt
  # One machine the compiler produces artifacts for, and the roof over everything beside
  # this file: the instruction sets, the substrates, the machines and the bindings are all
  # here to be composed, and this is where the composing is done. The name is the whole
  # identity of a target — it is what the command line spells and the directory the
  # artifacts land in, so there is never a second vocabulary to translate between.
  #
  # Underneath the name a target is a composition of four answers, and they are kept apart
  # because none of them decides another:
  #
  #   isa       — the instruction set, named by its triple
  #   substrate — what lies underneath, which settles whether the program ends
  #   binding   — the implementation that answers, written in the words of what is called
  #   machine   — what the artifact runs on, and what can be reached there
  #
  # One binding serves machines that share no instruction set, one machine is reachable
  # through more than one of them, and an instruction set says nothing about whether an
  # operating system is underneath it. Naming the four separately is what keeps a machine
  # whose instruction set is WebAssembly, and a desktop whose peripherals are all stubs,
  # from each needing a kind of their own. Nothing is inferred here: a target that leaves
  # an answer out is a target nobody has decided about yet.
  #
  # **No target is written here.** This file knows how a target is put together and knows
  # nothing about any particular one — every composition arrives from the binding that can
  # produce it, by calling `register`. What is left is the shape of the thing and a table
  # that fills itself, which is what lets a machine be taught to this compiler without the
  # compiler being taught about the machine.
  class Target
    OPTION_PREFIX = "--target="
    DEFAULT_NAMES = ["host"].freeze

    attr_reader :name, :isa, :substrate, :binding, :machine

    def initialize(name, isa:, substrate:, binding:, machine:)
      @name = name
      @isa = isa
      @substrate = substrate
      @binding = binding
      @machine = machine
    end

    # Where the artifacts land. Three of the four answers are spelled out, because three
    # of them can differ while the rest agree: one machine reached through two bindings,
    # and one machine built for either of the two instruction sets its chip carries, are
    # different firmware that must not overwrite each other. The substrate is left out
    # because the triple already carries it. It is long, and that length is the information.
    def directory = "#{@machine.key}-#{@binding.key}-#{@isa.triple}"

    TABLE = {}

    # The full names are what the artifacts are named after and what the documents say.
    # A short form is for typing at a prompt, and earns its place by being short.
    ALIASES = {}

    def self.register(name, isa:, substrate:, binding:, machine:, short: nil)
      ALIASES[short] = name if short
      TABLE[name] = new(name, isa: isa, substrate: substrate, binding: binding, machine: machine)
    end

    def self.[](name) = TABLE.fetch(ALIASES.fetch(name, name))

    # A run compiles exactly what it was asked for. Nothing is read from a file and
    # nothing is merged in behind the request, so what a command line says is the whole
    # of what happens; with nothing said, the machine doing the compiling is the target.
    def self.select(options)
      names = options.map { |option| option.delete_prefix(OPTION_PREFIX) }
      names = DEFAULT_NAMES if names.empty?
      names.map { |name| self[name] }.uniq
    end

    # Where a binding declares itself. Nothing here says which bindings exist — they are
    # found by looking rather than by naming, which is what lets one be added without this
    # file changing.
    #
    # **There is one place, and the binding this side owns is not privileged in it.** While
    # the compiler was a tree rather than a gem, host lived beside this file and everything
    # else lived where a gem lives, and the two had to be looked for separately. Now that
    # this side is a gem too, beside itself *is* where a gem lives: host is found by the
    # same glob that finds a Pico, from the same path, with nothing to tell them apart.
    DECLARATIONS = "bareruby_prot/binding/*/targets.rb"

    # **A binding is found once even when it is reachable twice.** Looking in every gem
    # means looking in copies of one: a checkout that carries a gem in its working tree
    # and has the same gem installed sees both, and loading both redefines every constant
    # in it. Which binding a declaration is for is the name of the directory it sits in,
    # and the first one found wins — the load path is searched before the installed gems,
    # so a working tree beats a copy of itself.
    def self.declarations = Gem.find_files(DECLARATIONS).uniq { |one| named(one) }.sort_by { |one| named(one) }

    def self.named(declaration) = File.basename(File.dirname(declaration))

    def self.load_bindings = declarations.each { |one| require one }
  end
end

BareRubyProt::Target.load_bindings
