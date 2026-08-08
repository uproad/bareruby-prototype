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
  # will be. One thing in it is not the same on two desks and is written here: which
  # machine is doing the compiling. Where the gems come from is the same everywhere — the
  # Gemfile names the repository — so what this writes is a project any desk can build,
  # including one that has never held a checkout of this.
  class Scaffold
    TEMPLATE = File.expand_path("../../new_template", __dir__)

    # A dot file cannot be shipped under its own name: it would take effect in the
    # repository that ships it, and hide from git the very files it is meant to carry.
    RENAMED = { "gitignore" => ".gitignore" }.freeze

    def self.run(arguments) = new(arguments.first).run

    def initialize(name)
      @name = name
      @directory = File.expand_path(name.to_s, Dir.pwd)
    end

    def run
      return over if over?

      copy
      written
      install
      said
      0
    end

    # **The one thing this command must not do is write over the files it wrote before.**
    # Those are exactly the files a project is edited in — the program, the Gemfile the
    # boards are uncommented in, the record. `new NAME` is easy to type a second time: out
    # of shell history, or after a first attempt stopped partway. Landing on a project and
    # returning zero would take a day's work with it and say nothing.
    #
    # What is in the way is named rather than counted, and nothing is written at all — a
    # command that stopped halfway through would leave a tree that is neither.
    def over? = holding.any?

    def holding = writes.select { |name| File.exist?(at(name)) }

    # What the template lands as, which is not quite what it carries: the dot file arrives
    # under its own name.
    def writes
      Dir.glob("**/*", File::FNM_DOTMATCH, base: TEMPLATE)
         .select { |name| File.file?(File.join(TEMPLATE, name)) }
         .map { |name| RENAMED.fetch(name, name) }
    end

    def over
      warn "bareruby: #{@directory} already holds #{holding.sort.join(', ')}."
      warn "bareruby: nothing was written. A project is made in a directory that has none " \
           "of those."
      1
    end

    def copy
      FileUtils.mkdir_p(@directory)
      FileUtils.cp_r(File.join(TEMPLATE, "."), @directory)
    end

    # The one answer no template can hold, and the one name no gem may be shipped under.
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

    def filled(text) = text.gsub("__TRIPLE__", Target["host"].isa.triple)

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
