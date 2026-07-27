uart = UART.new(0, baud: 115200, parity: UART::NONE)

arena(size: 256) do |a|
  header = uart.read(4)
  line = uart.gets

  puts header
  puts header.size
  puts line
  puts line.size
end
