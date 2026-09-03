# frozen_string_literal: true

require "bareruby_prot/binding/arduino/version"

# What the gemspec reads to say which version this is. Nothing else requires it, so
# a version file that stopped loading would be noticed here and at `gem build`.
RSpec.describe BareRubyProt::Binding::Arduino do
  it "has a version number" do
    expect(BareRubyProt::Binding::Arduino::VERSION).not_to be_nil
  end
end
