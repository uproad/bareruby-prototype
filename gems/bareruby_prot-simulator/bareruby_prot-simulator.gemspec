# frozen_string_literal: true

# The machine the host build has no board to run on, packaged: an interpreter for the
# instructions the compiling desk speaks, and a board made of Ruby objects behind the
# calls a program makes into a peripheral. It depends on nothing, because what it reads
# is an artifact rather than a compilation — the ELF a build left, and nothing that
# produced it.
#
# The name carries the prototype's own prefix rather than the one the real compiler will
# use, because this is a throwaway and has no business holding that name anywhere.
Gem::Specification.new do |spec|
  spec.name = "bareruby_prot-simulator"
  spec.version = "0.0.1"
  spec.summary = "Runs a host build with no board, on a board made of Ruby objects."
  spec.authors = ["uproad"]
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0"

  # The gemspec ships inside the gem: a project written by `new` reads these gems from
  # where they are, and to bundler a directory with no gemspec in it is not a gem.
  spec.files = Dir["*.gemspec"] + Dir["*.md"] + Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]

  spec.metadata = { "rubygems_mfa_required" => "true" }
end
