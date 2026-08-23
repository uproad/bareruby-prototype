uart = UART.new(unit: 0, baudrate: 115_200, data_bits: 8, parity: UART::NONE, stop_bits: 1)

uart.setmode(baudrate: 9_600)
puts uart.baudrate
