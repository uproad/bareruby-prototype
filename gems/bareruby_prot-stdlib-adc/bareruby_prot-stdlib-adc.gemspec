# frozen_string_literal: true

# One class the language offers, packaged. Nothing in the compiler names it: it is found
# because it is installed, at the path every standard class is looked for under.
#
# The name carries the prototype's own prefix rather than the one the real compiler will
# use, because this is a throwaway and has no business holding that name anywhere.
Gem::Specification.new do |spec|
  spec.name = "bareruby_prot-stdlib-adc"
  spec.version = "0.0.1"
  spec.summary = "The ADC class: what a program may read off a pin, and what that lowers to."
  spec.authors = ["uproad"]
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0"

  # The gemspec ships inside the gem: a project written by `new` reads these gems from
  # where they are, and to bundler a directory with no gemspec in it is not a gem.
  spec.files = Dir["*.gemspec"] + Dir["lib/**/*.rb"]
  spec.require_paths = ["lib"]
  # **What this needs to be read at all.** The declaration form, the registry it registers
  # into and the vocabulary it is written in are the first stage's, so a class is
  # meaningless without it. A user never writes this line in a Gemfile: naming the class is
  # what brings the compiler with it.
  spec.add_dependency "bareruby_prot-compiler", ">= 0.0.1"

  spec.metadata = { "rubygems_mfa_required" => "true" }
end
