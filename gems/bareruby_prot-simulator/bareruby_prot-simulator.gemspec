# frozen_string_literal: true

# The other half of `binding: host`, packaged: an interpreter for the instructions the
# compiling desk speaks, and the peripherals that desk carries behind the calls a program
# makes into one. It depends on nothing, because what it reads is an artifact rather than
# a compilation — the ELF a build left, and nothing that produced it.
#
# The name carries the prototype's own prefix rather than the one the real compiler will
# use, because this is a throwaway and has no business holding that name anywhere.
require_relative "lib/bareruby_prot/simulator/version"

Gem::Specification.new do |spec|
  spec.name = "bareruby_prot-simulator"
  spec.version = BareRubyProt::Simulator::VERSION
  spec.authors = ["uproad"]
  spec.email = ["7349115+uproad@users.noreply.github.com"]

  spec.summary = "Interprets a host build, with the desk's own peripherals behind its calls."
  spec.description = "Interprets the artifact a host build left, with the desk's own peripherals behind its calls."
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
end
