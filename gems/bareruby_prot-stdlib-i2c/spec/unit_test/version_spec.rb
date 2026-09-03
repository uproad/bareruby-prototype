# frozen_string_literal: true

require "bareruby_prot/stdlib/i2c/version"

# What the gemspec reads to say which version this is. Nothing else requires it, so
# a version file that stopped loading would be noticed here and at `gem build`.
RSpec.describe BareRubyProt::Stdlib::I2c do
  it "has a version number" do
    expect(BareRubyProt::Stdlib::I2c::VERSION).not_to be_nil
  end
end
