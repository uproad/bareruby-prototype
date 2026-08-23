uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE, rx_buffer_size: 8)

uart.bytes_available
sleep_ms 20
puts uart.bytes_available
puts uart.getbyte
puts uart.getbyte
puts uart.getbyte
puts uart.getbyte

sleep_ms 20
puts uart.bytes_available
puts uart.getbyte
puts uart.getbyte
puts uart.getbyte
puts uart.getbyte
puts uart.getbyte
puts uart.getbyte
puts uart.getbyte
