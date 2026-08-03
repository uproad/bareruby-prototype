# frozen_string_literal: true

module BareRubyProt
  class Machine
    # Arduino Mega 2560, and the compatible boards built to the same design. The one
    # verified here is an ELEGOO MEGA 2560 R3, which carries the same chip and the same
    # USB-serial bridge and answers to Arduino's own vendor and product ids, so nothing
    # on this side can tell it from the board it copies.
    MEGA2560 = new(:mega2560, chip: "atmega2560")
  end
end
