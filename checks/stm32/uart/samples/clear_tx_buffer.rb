uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE)

uart.write "AB"
uart.clear_tx_buffer
uart.puts "C"
