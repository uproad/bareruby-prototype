# frozen_string_literal: true

# One binding, packaged. Nothing in the compiler names it: it is found because it is
# installed, at the path every binding is looked for under.
#
# The name carries the prototype's own prefix rather than the one the real compiler will
# use, because this is a throwaway and has no business holding that name anywhere.
Gem::Specification.new do |spec|
  spec.name = "bareruby_prot-binding-pico_sdk"
  spec.version = "0.0.1"
  spec.summary = "Reaches Raspberry Pi Pico boards through pico-sdk."
  spec.authors = ["uproad"]
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  # The C++ lives in the Ruby as heredocs, but the flashing script and the family it
  # offers are files, and a gem carries only what it lists.
  spec.files = Dir["lib/**/*.{rb,sh,yml}"]
  spec.require_paths = ["lib"]
  spec.metadata = { "rubygems_mfa_required" => "true" }
end
