# frozen_string_literal: true

require "bundler"

module BareRubyProt
  # Where the project is. Everything a run reaches for that it did not bring with it — the
  # desk's record under config/, the source it compiles, the directories it writes — is
  # found from one place, and that place is where the Gemfile is.
  #
  # **Bundler already answers this.** A project names bareruby in its Gemfile and runs it
  # through the binstub beside it, so by the time this executable exists at all, the root
  # has been found by something that had to find it anyway. Nothing here walks a tree
  # looking for a marker, and nothing has to decide what would count as one.
  #
  # That matters most for the file that is allowed to be missing. A desk that has recorded
  # nothing and a run that has lost its way say the same thing when the record is looked
  # for beside the wrong directory, and the second one is silent: the build succeeds and
  # leaves its artifacts somewhere nobody asked for. Asking bundler removes the question
  # rather than answering it — a run that cannot find the root does not get this far.
  #
  # The process is stood at the root rather than the root being handed around, because the
  # compiler is another gem and knows nothing about projects. It writes beside where it
  # was run, and being stood in the right place is all it needs to be told.
  module Project
    # `new` is the one command with no project to stand in, because it is what makes one.
    ROOTLESS = %w[new].freeze

    def self.stand(arguments)
      return if ROOTLESS.include?(arguments.first)

      # Named before the ground moves. A source given relative to where it was typed means
      # that place, not the root the next line steps to.
      arguments.map! { |word| word.end_with?(".rb") ? File.expand_path(word) : word }
      Dir.chdir(Bundler.root)
    end
  end
end
