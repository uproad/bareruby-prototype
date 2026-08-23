uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE)
uart.line_ending = "\r\n"

arena(256) do
  line = uart.gets
  puts line.size
end
puts uart.getbyte
