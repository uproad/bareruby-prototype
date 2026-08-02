# frozen_string_literal: true

module BareRubyProt
  # What lies underneath the program, which settles one question the generated entry point
  # cannot avoid: whether the program ends. A hosted program returns to whatever started
  # it, and falling off the end of it is the run finishing. A bare-metal program has
  # nowhere to return to, so it idles instead.
  #
  # Which symbol the entry point is called, and whether this side writes it at all, is a
  # different question and belongs to the binding — that is the side that knows who owns
  # main. Keeping the two apart is what lets a firmware environment that calls into the
  # program, and an operating system that launches it, be described without either one
  # becoming a special case of the other.
  class Substrate
    attr_reader :name

    def initialize(name, terminates:)
      @name = name
      @terminates = terminates
    end

    def terminates? = @terminates

    HOSTED = new("hosted", terminates: true)
    BARE_METAL = new("bare-metal", terminates: false)
  end
end
