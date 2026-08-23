uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE)

uart.bytes_available
sleep_ms 20
puts uart.bytes_available
uart.clear_rx_buffer
puts uart.bytes_available
puts uart.peek
puts uart.getbyte

sleep_ms 20
puts uart.bytes_available
puts uart.getbyte
