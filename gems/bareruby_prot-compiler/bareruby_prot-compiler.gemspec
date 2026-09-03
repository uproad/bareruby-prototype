# frozen_string_literal: true

# The first stage, packaged: every pass, the intermediate representations, the language
# runtime, and the vocabulary a composition is spelled in. It carries exactly one binding —
# the one that needs no hardware — and will never carry another.
#
# The name carries the prototype's own prefix rather than the one the real compiler will
# use, because this is a throwaway and has no business holding that name anywhere.
require_relative "lib/bareruby_prot/compiler/version"

Gem::Specification.new do |spec|
  spec.name = "bareruby_prot-compiler"
  spec.version = BareRubyProt::Compiler::VERSION
  spec.authors = ["uproad"]
  spec.email = ["7349115+uproad@users.noreply.github.com"]

  spec.summary = "Compiles BareRuby to C++, and declares what a binding answers."
  spec.description = "Reads BareRuby through every pass to C++, and declares what a binding must answer."
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
  spec.files = Dir["*.gemspec", "*.md", "Rakefile", "exe/**/*", "lib/**/*", "sig/**/*"]
               .select { |path| File.file?(path) }
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{\Aexe/}) { |path| File.basename(path) }
  spec.require_paths = ["lib"]

  # The only thing outside this gem that reading a program needs.
  spec.add_dependency "prism"
end
