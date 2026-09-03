# frozen_string_literal: true

# One class the language offers, packaged. Nothing in the compiler names it: it is found
# because it is installed, at the path every standard class is looked for under.
#
# The name carries the prototype's own prefix rather than the one the real compiler will
# use, because this is a throwaway and has no business holding that name anywhere.
require_relative "lib/bareruby_prot/stdlib/onboard_led/version"

Gem::Specification.new do |spec|
  spec.name = "bareruby_prot-stdlib-onboard_led"
  spec.version = BareRubyProt::Stdlib::OnboardLed::VERSION
  spec.authors = ["uproad"]
  spec.email = ["7349115+uproad@users.noreply.github.com"]

  spec.summary = "The OnboardLED class: the indicator a board carries, wherever it is, and what that lowers to."
  spec.description = "The OnboardLED class: the indicator a board carries, whatever drives it."
  spec.homepage = "https://github.com/uproad/bareruby-prototype"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  # The gemspec ships inside the gem: a project written by `new` reads these gems from
  # where they are, and to bundler a directory with no gemspec in it is not a gem.
  spec.files = Dir["*.gemspec"] + Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]

  # **What this needs to be read at all.** The declaration form, the registry it registers
  # into and the vocabulary it is written in are the first stage's, so a class is
  # meaningless without it. A user never writes this line in a Gemfile: naming the class is
  # what brings the compiler with it.
  spec.add_dependency "bareruby_prot-compiler"
end
