uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE)

arena(256) do
  taken = uart.read(4)
  uart.puts taken
  puts taken.size
end
puts uart.bytes_available
