uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE)

uart.puts "sent"
uart.flush
puts uart.bytes_to_write
