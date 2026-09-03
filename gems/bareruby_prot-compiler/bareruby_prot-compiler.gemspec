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

  # The gemspec ships inside the gem: a project written by `new` reads these gems from
  # where they are, and to bundler a directory with no gemspec in it is not a gem.
  spec.files = Dir["*.gemspec"] + Dir["lib/**/*.{rb,yml}"]
  spec.require_paths = ["lib"]

  # The only thing outside this gem that reading a program needs.
  spec.add_dependency "prism"
end
