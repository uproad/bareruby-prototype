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
    # **The commands that need a project, named rather than the ones that do not.** Listing
    # the exceptions puts the harmful answer on the default: `new` makes a project and
    # cannot be standing in one, printing the usage needs nothing at all, and a misspelt
    # command is neither — all three would be asked for a root they have no reason to have,
    # and the first thing anyone types after installing is one of them. Named this way
    # round, a command that is not on this list is simply run where it was typed.
    # `target add` writes into the project and `target list` says what that project could
    # record, so both belong to one, and the verb is not enough to answer for either half
    # of the pair on its own.
    ROOTED = ["compile", "build", "flash", "deploy", "init",
              "target add", "target list", "tools install"].freeze

    # **What a run can see is what this project's bundle holds.** A gem installed at the
    # desk for some other project is not part of this answer — not even by existing. A
    # desk carries several projects, each holding a version of the same gem, and a
    # declaration that differs by a version is C++ that differs by a version: what would
    # arrive is not a longer list but somebody else's program. Standing the run in the
    # bundle is the whole of the answer, because then nothing downstream has to ask which
    # gems were the project's — the ones it can reach are the only ones there are.
    def self.stand(arguments)
      return if (ROOTED & [arguments.first, arguments.take(2).join(" ")]).empty?

      # Named before the ground moves. A source given relative to where it was typed means
      # that place, not the root the next line steps to.
      arguments.map! { |word| word.end_with?(".rb") ? File.expand_path(word) : word }
      Bundler.setup
      Dir.chdir(Bundler.root)
    end
  end
end
