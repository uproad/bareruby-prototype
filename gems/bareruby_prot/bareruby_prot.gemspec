# frozen_string_literal: true

# The ecosystem: everything a user types, and everything that happens after the first
# stage has written its C++. It knows nothing about how a program is read or lowered, and
# nothing about how any machine is reached — it runs the compiler, and it runs whichever
# binding the composition names.
#
# The name carries the prototype's own prefix rather than the one the real ecosystem will
# use, because this is a throwaway and has no business holding that name anywhere.
Gem::Specification.new do |spec|
  spec.name = "bareruby_prot"
  spec.version = "0.0.1"
  spec.summary = "Runs BareRuby: the compiler, the second stage, and what a desk is."
  spec.authors = ["uproad"]
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]

  # The one executable, and the only way into any of this from a shell.
  spec.bindir = "exe"
  spec.executables = ["bareruby"]

  # A user installs this one and gets a compiler with it. The other way round is not true:
  # a compiler is usable without anything that runs a second stage.
  spec.add_dependency "bareruby_prot-compiler"

  spec.metadata = { "rubygems_mfa_required" => "true" }
end
