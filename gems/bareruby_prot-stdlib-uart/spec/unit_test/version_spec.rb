# frozen_string_literal: true

require "bareruby_prot/stdlib/uart/version"

# What the gemspec reads to say which version this is. Nothing else requires it, so
# a version file that stopped loading would be noticed here and at `gem build`.
RSpec.describe BareRubyProt::Stdlib::Uart do
  it "has a version number" do
    expect(BareRubyProt::Stdlib::Uart::VERSION).not_to be_nil
  end
end
