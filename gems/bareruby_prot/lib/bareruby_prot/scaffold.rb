# frozen_string_literal: true

require "fileutils"

require "bareruby_prot/target/target"

module BareRubyProt
  # `bareruby new`. The first thing a user meets, and the only command that runs where
  # there is no project yet.
  #
  # **The tree it writes builds without being edited.** A host entry in the record and an
  # onboard LED in app/main.rb, so the first success comes before any hardware is bought;
  # reaching a board after that is one comment character in the Gemfile and a
  # `bundle install`. Everything a project needs to know about where it stands — its root,
  # its record, its sources — is decided by that Gemfile existing.
  #
  # The template is files rather than strings, so what a user gets can be read as what it
  # will be. Two things in it are not the same on two desks and are written here: where
  # the gems come from, and which machine is doing the compiling.
  class Scaffold
    TEMPLATE = File.expand_path("../../new_template", __dir__)

    # A dot file cannot be shipped under its own name: it would take effect in the
    # repository that ships it, and hide from git the very files it is meant to carry.
    RENAMED = { "gitignore" => ".gitignore" }.freeze

    # Where the gems are read from. The prototype publishes nothing, so a project points
    # at the checkout its `new` came out of. Released, this is what a version would be.
    GEMS = File.expand_path("../../..", __dir__)

    def self.run(arguments) = new(arguments.first).run

    def initialize(name)
      @name = name
      @directory = File.expand_path(name.to_s, Dir.pwd)
    end

    def run
      copy
      written
      install
      said
      0
    end

    def copy
      FileUtils.mkdir_p(@directory)
      FileUtils.cp_r(File.join(TEMPLATE, "."), @directory)
    end

    # The two answers no template can hold, and the one name no gem may be shipped under.
    #
    # **The template says which files these are, not the directory they were copied into.**
    # Asking the destination what it holds makes the work depend on what was already there,
    # and a `new` that landed on a directory full of someone else's files would rewrite
    # every one of them.
    def written
      copied.each { |path| File.write(path, filled(File.read(path))) }
      RENAMED.each { |from, to| FileUtils.mv(at(from), at(to)) }
    end

    def copied
      Dir.glob("**/*", File::FNM_DOTMATCH, base: TEMPLATE)
         .map { |name| at(name) }.select { |path| File.file?(path) }
    end

    def filled(text)
      text.gsub("__GEMS__", GEMS).gsub("__TRIPLE__", Target["host"].isa.triple)
    end

    def at(name) = File.join(@directory, name)

    # Resolved and made runnable here rather than left for the user, so that the tree is
    # buildable the moment this command returns. The binstub is what makes the root
    # findable from anywhere inside the project afterwards.
    def install
      Bundler.with_unbundled_env do
        Dir.chdir(@directory) do
          system("bundle", "install", "--quiet", exception: true)
          system("bundle", "binstubs", "bareruby_prot", exception: true)
        end
      end
    end

    def said
      puts <<~SAID
        Created #{@directory}

          cd #{@name}
          bin/bareruby build          # builds and runs on this machine, unedited
          bin/bareruby target add     # once a board is uncommented in the Gemfile
      SAID
    end
  end
end
