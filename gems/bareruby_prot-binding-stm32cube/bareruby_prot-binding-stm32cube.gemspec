# frozen_string_literal: true

# One binding, packaged. Nothing in the compiler names it: it is found because it is
# installed, at the path every binding is looked for under.
#
# The name carries the prototype's own prefix rather than the one the real compiler will
# use, because this is a throwaway and has no business holding that name anywhere.
require_relative "lib/bareruby_prot/binding/stm32cube/version"

Gem::Specification.new do |spec|
  spec.name = "bareruby_prot-binding-stm32cube"
  spec.version = BareRubyProt::Binding::Stm32cube::VERSION
  spec.authors = ["uproad"]
  spec.email = ["7349115+uproad@users.noreply.github.com"]

  spec.summary = "Reaches STM32 boards through the STM32Cube HAL, from manifests this gem carries."
  spec.description = "Reaches STM32 boards through STM32Cube: what it builds with, how it flashes, and how it emulates."
  spec.homepage = "https://github.com/uproad/bareruby-prototype"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 4.0"

  spec.metadata["homepage_uri"] = spec.homepage
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["rubygems_mfa_required"] = "true"

  # The C lives in the Ruby as heredocs, but the device and board manifests are data,
  # the installer is a script, and the linker layout is a template. A gem carries only
  # what it lists, and this binding is mostly what it describes.
  #
  # The prose travels too. The gemspec ships inside the gem: a project written by `new`
  # reads these gems from where they are, and to bundler a directory with no gemspec in
  # it is not a gem.
  spec.files = Dir["*.gemspec"] + Dir["lib/**/*.{rb,sh,yml,erb}"] +
               ["README.md", "readme_jp.md", "setup.md", "build.md"]
  spec.require_paths = ["lib"]

  # **What this needs to be read at all — both public faces.** A binding is written in the
  # words of what it calls, which is the first stage's vocabulary, and it starts a second
  # stage and writes a machine, which is the ecosystem's. Naming both is what the line
  # crossed here costs; a user who uncomments this gem in a Gemfile gets both with it.
  spec.add_dependency "bareruby_prot"

  spec.add_dependency "bareruby_prot-compiler"
end
