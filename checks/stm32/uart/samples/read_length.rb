uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE)

arena(256) do
  received = uart.read(3)
  uart.puts received
  puts received.size
end
puts uart.bytes_available
puts uart.getbyte
