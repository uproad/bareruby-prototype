# frozen_string_literal: true

require "bareruby_prot/stdlib/i2c"

# The one thing a standard class needs from outside itself: the registration the compiler
# offers. A compiler the bundle resolved from anywhere but the declared range would fail
# here rather than silently answer to a different vocabulary.
RSpec.describe "the compiler this suite resolves" do
  it "accepts this gem's registration" do
    expect(BareRubyProt::Peripheral.known?(:I2C)).to be true
  end
end
