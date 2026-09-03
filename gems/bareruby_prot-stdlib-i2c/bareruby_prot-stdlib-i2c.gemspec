# frozen_string_literal: true

# One class the language offers, packaged. Nothing in the compiler names it: it is found
# because it is installed, at the path every standard class is looked for under.
#
# The name carries the prototype's own prefix rather than the one the real compiler will
# use, because this is a throwaway and has no business holding that name anywhere.
require_relative "lib/bareruby_prot/stdlib/i2c/version"

Gem::Specification.new do |spec|
  spec.name = "bareruby_prot-stdlib-i2c"
  spec.version = BareRubyProt::Stdlib::I2c::VERSION
  spec.authors = ["uproad"]
  spec.email = ["7349115+uproad@users.noreply.github.com"]

  spec.summary = "The I2C class: what a program may say to a bus, and what that lowers to."
  spec.description = "The I2C class: what a program may say on a bus, and what that lowers to."
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

  # **What this needs to be read at all.** The declaration form, the registry it registers
  # into and the vocabulary it is written in are the first stage's, so a class is
  # meaningless without it. A user never writes this line in a Gemfile: naming the class is
  # what brings the compiler with it.
  spec.add_dependency "bareruby_prot-compiler", ">= 0.0.1"
end
