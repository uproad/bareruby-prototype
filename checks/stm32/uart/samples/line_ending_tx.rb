uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE)

uart.line_ending = "\r\n"
uart.puts "OK"
