# frozen_string_literal: true

# The other half of `binding: host`, packaged: an interpreter for the instructions the
# compiling desk speaks, and the peripherals that desk carries behind the calls a program
# makes into one. It depends on nothing, because what it reads is an artifact rather than
# a compilation — the ELF a build left, and nothing that produced it.
#
# The name carries the prototype's own prefix rather than the one the real compiler will
# use, because this is a throwaway and has no business holding that name anywhere.
Gem::Specification.new do |spec|
  spec.name = "bareruby_prot-simulator"
  spec.version = "0.0.1"
  spec.summary = "Interprets a host build, with the desk's own peripherals behind its calls."
  spec.authors = ["uproad"]
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0"

  # The gemspec ships inside the gem: a project written by `new` reads these gems from
  # where they are, and to bundler a directory with no gemspec in it is not a gem.
  spec.files = Dir["*.gemspec"] + Dir["*.md"] + Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]

  spec.metadata = { "rubygems_mfa_required" => "true" }
end
