# frozen_string_literal: true

# One binding, packaged. Nothing in the compiler names it: it is found because it is
# installed, at the path every binding is looked for under.
#
# The name carries the prototype's own prefix rather than the one the real compiler will
# use, because this is a throwaway and has no business holding that name anywhere.
Gem::Specification.new do |spec|
  spec.name = "bareruby_prot-binding-arduino"
  spec.version = "0.0.1"
  spec.summary = "Reaches Arduino boards through the Arduino core."
  spec.authors = ["uproad"]
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0"

  # The C++ lives in the Ruby as heredocs, but the family this binding offers is a file,
  # and a gem carries only what it lists. What this core cannot be asked for is a fact
  # somebody installing this needs, so the README travels with it.
  # The gemspec ships inside the gem: a project written by `new` reads these gems from
  # where they are, and to bundler a directory with no gemspec in it is not a gem.
  spec.files = Dir["*.gemspec"] + Dir["lib/**/*.{rb,yml}"] + ["README.md"]
  spec.require_paths = ["lib"]
  # **What this needs to be read at all — both public faces.** A binding is written in the
  # words of what it calls, which is the first stage's vocabulary, and it starts a second
  # stage and writes a machine, which is the ecosystem's. Naming both is what the line
  # crossed here costs; a user who uncomments this gem in a Gemfile gets both with it.
  spec.add_dependency "bareruby_prot", ">= 0.0.1", "< 0.1.0"
  spec.add_dependency "bareruby_prot-compiler", ">= 0.0.1", "< 0.1.0"

  spec.metadata = { "rubygems_mfa_required" => "true" }
end
