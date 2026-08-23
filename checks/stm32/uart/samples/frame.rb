uart = UART.new(unit: 0, baudrate: 9_600, data_bits: 7, parity: UART::EVEN, stop_bits: 1)

uart.puts "configured"
