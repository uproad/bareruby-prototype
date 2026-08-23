uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE)

written = uart.write "ABC"
puts written
