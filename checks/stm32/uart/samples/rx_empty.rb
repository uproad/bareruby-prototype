uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE)

puts uart.bytes_available
puts uart.peek
puts uart.getbyte
