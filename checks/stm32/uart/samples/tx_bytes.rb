uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE)

uart.write "ABC"
uart.puts "DEF"
