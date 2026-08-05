# frozen_string_literal: true

# The first stage, packaged: every pass, the intermediate representations, the language
# runtime, and the vocabulary a composition is spelled in. It carries exactly one binding —
# the one that needs no hardware — and will never carry another.
#
# The name carries the prototype's own prefix rather than the one the real compiler will
# use, because this is a throwaway and has no business holding that name anywhere.
Gem::Specification.new do |spec|
  spec.name = "bareruby_prot-compiler"
  spec.version = "0.0.1"
  spec.summary = "Compiles BareRuby to C++, and declares what a binding answers."
  spec.authors = ["uproad"]
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0"

  spec.files = Dir["lib/**/*.{rb,yml}"]
  spec.require_paths = ["lib"]

  # The only thing outside this gem that reading a program needs.
  spec.add_dependency "prism"

  spec.metadata = { "rubygems_mfa_required" => "true" }
end
