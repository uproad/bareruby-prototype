uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE)

arena(256) do
  line = uart.gets
  uart.write line
  puts line.size
end
puts uart.bytes_available
