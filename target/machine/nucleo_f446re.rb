# frozen_string_literal: true

module BareRubyProt
  class Machine
    # ST NUCLEO-F446RE
    NUCLEO_F446RE = new("NUCLEO-F446RE", chip: "stm32f446", led: :stm32)
  end
end
