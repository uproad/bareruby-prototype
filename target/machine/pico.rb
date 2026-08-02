# frozen_string_literal: true

module BareRubyProt
  class Machine
    # Raspberry Pi Pico
    PICO = new("pico", chip: "rp2040", led: :pin)
  end
end
