# frozen_string_literal: true

require "bareruby_prot/stdlib/onboard_led/version"

# What the gemspec reads to say which version this is. Nothing else requires it, so
# a version file that stopped loading would be noticed here and at `gem build`.
RSpec.describe BareRubyProt::Stdlib::OnboardLed do
  it "has a version number" do
    expect(BareRubyProt::Stdlib::OnboardLed::VERSION).not_to be_nil
  end
end
