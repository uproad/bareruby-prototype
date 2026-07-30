uart = UART.new(0, baud: 115200, parity: UART::NONE)

arena(256) do
  header = uart.read(4)
  line = uart.gets

  puts header
  puts header.size
  puts line
  puts line.size
end
