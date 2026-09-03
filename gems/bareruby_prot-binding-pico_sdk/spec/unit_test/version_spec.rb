# frozen_string_literal: true

require "bareruby_prot/binding/pico_sdk/version"

# What the gemspec reads to say which version this is. Nothing else requires it, so
# a version file that stopped loading would be noticed here and at `gem build`.
RSpec.describe BareRubyProt::Binding::PicoSdk do
  it "has a version number" do
    expect(BareRubyProt::Binding::PicoSdk::VERSION).not_to be_nil
  end
end
