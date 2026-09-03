# frozen_string_literal: true

# The one thing a standard class needs from outside itself: the registration the compiler
# offers. A compiler that no longer answers to it fails here rather than silently letting
# this class register into a different vocabulary.
RSpec.describe "the compiler this suite resolves" do
  it "accepts this gem's registration" do
    expect(BareRubyProt::Peripheral.known?(:UART)).to be true
  end
end
