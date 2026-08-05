# frozen_string_literal: true

# One binding, packaged. Nothing in the compiler names it: it is found because it is
# installed, at the path every binding is looked for under.
#
# The name carries the prototype's own prefix rather than the one the real compiler will
# use, because this is a throwaway and has no business holding that name anywhere.
Gem::Specification.new do |spec|
  spec.name = "bareruby_prot-binding-stm32cube"
  spec.version = "0.0.1"
  spec.summary = "Reaches ST NUCLEO boards through a CubeMX project and the STM32Cube HAL."
  spec.authors = ["uproad"]
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.4"

  # The C++ lives in the Ruby as heredocs, but the bridge that synchronizes a build into a
  # CubeMX project is a script, the header that project includes is a header, and the
  # family this binding offers is a file. A gem carries only what it lists.
  #
  # The prose travels too. This is the one binding that cannot work until the desk has
  # prepared a project by hand, and what to prepare is the whole of setup.md.
  spec.files = Dir["lib/**/*.{rb,sh,yml,h}"] + ["README.md", "setup.md", "build.md"]
  spec.require_paths = ["lib"]
  spec.metadata = { "rubygems_mfa_required" => "true" }
end
