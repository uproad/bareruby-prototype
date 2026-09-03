# frozen_string_literal: true

# The ecosystem: everything a user types, and everything that happens after the first
# stage has written its C++. It knows nothing about how a program is read or lowered, and
# nothing about how any machine is reached — it runs the compiler, and it runs whichever
# binding the composition names.
#
# The name carries the prototype's own prefix rather than the one the real ecosystem will
# use, because this is a throwaway and has no business holding that name anywhere.
require_relative "lib/bareruby_prot/version"

Gem::Specification.new do |spec|
  spec.name = "bareruby_prot"
  spec.version = BareRubyProt::VERSION
  spec.authors = ["uproad"]
  spec.email = ["7349115+uproad@users.noreply.github.com"]

  spec.summary = "Runs BareRuby: the compiler, the second stage, and what a desk is."
  spec.description = "Runs the compiler, starts a second stage, flashes a board, and holds what a desk is."
  spec.homepage = "https://github.com/uproad/bareruby-prototype"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  # Specify which files should be added to the gem when it is released.
  #
  # **This is not the `git ls-files` the generator writes**, for two reasons. The gemspec
  # has to ship: a project reads these gems from where they are, and to bundler a directory
  # with no gemspec in it is not a gem. And this file is re-read from places git cannot
  # answer for — an unpacked `.gem` used as a path source is not a repository, and there
  # `git ls-files` returns nothing, which silently ships a gem with no files and no
  # executable.
# `new_template/` is in the list because the template `new` writes is shipped as files
# rather than as strings. Nothing requires it, so nothing here would notice it going
# missing: a project written out of a gem that left it behind is empty, and only a run
# that installs this gem and calls `new` says so.
spec.files = Dir["*.gemspec", "*.md", "Rakefile", "exe/**/*", "lib/**/*", "sig/**/*",
                 "new_template/**/*"].select { |path| File.file?(path) }
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |path| File.basename(path) }
  spec.require_paths = ["lib"]

  # A user installs this one and gets a compiler with it. The other way round is not true:
  # a compiler is usable without anything that runs a second stage.
  spec.add_dependency "bareruby_prot-compiler", ">= 0.0.1"
end
