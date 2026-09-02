# frozen_string_literal: true

require "bareruby_prot/cli"

# What the ecosystem reaches across the stage boundary for. Loading the command is what
# pulls the first stage in, so a compiler outside the declared range fails here rather
# than at the moment a user compiles something.
RSpec.describe "the compiler this suite resolves" do
  it "provides what the ecosystem loads" do
    expect(BareRubyProt::Compiler).to be_a(Class)
  end
end
