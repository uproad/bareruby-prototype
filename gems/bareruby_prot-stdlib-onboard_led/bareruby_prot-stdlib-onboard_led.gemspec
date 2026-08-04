# frozen_string_literal: true

# One class the language offers, packaged. Nothing in the compiler names it: it is found
# because it is installed, at the path every standard class is looked for under.
#
# The name carries the prototype's own prefix rather than the one the real compiler will
# use, because this is a throwaway and has no business holding that name anywhere.
Gem::Specification.new do |spec|
  spec.name = "bareruby_prot-stdlib-onboard_led"
  spec.version = "0.0.1"
  spec.summary = "The OnboardLED class: the indicator a board carries, wherever it is, and what that lowers to."
  spec.authors = ["uproad"]
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  spec.files = Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]
  spec.metadata = { "rubygems_mfa_required" => "true" }
end
