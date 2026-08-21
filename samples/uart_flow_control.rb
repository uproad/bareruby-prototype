# The spelling the standard guideline and PicoRuby use. The unit is named rather than
# counted from the front of the call, the line has a baud rate that can be read back, the
# pins are the program's where the chip lets them be, and the line can be asked for with
# flow control. A board whose pins are its own refuses rather than opening the line
# somewhere it was not asked for.
uart = UART.new(unit: 0, txd_pin: 0, rxd_pin: 1, baudrate: 115_200,
                flow_control: UART::RTSCTS, rts_pin: 3, cts_pin: 2)

puts "opened at #{uart.baudrate}"

uart.puts "hello"
