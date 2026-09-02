# frozen_string_literal: true

require "bareruby_prot/peripheral"

# The promise every standard class is written against, checked on the side that makes it.
RSpec.describe BareRubyProt::Peripheral do
  it "offers the registration a standard class declares itself with" do
    expect(described_class).to respond_to(:register)
  end
end
