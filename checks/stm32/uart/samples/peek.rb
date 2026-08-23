uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE)

puts uart.peek
puts uart.peek
puts uart.getbyte
puts uart.bytes_available
