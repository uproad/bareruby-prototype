uart = UART.new(unit: 0, baudrate: 19_200, data_bits: 7, parity: UART::ODD, stop_bits: 2)

uart.puts "7O2 ready"
