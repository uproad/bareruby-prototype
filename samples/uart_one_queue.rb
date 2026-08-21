# One queue, and everyone reads it. peek, gets and bytes_available all answer about the
# same bytes, whichever asks first is the one that gets them, and what nobody took is
# still there afterwards. Feed it 'A\nBCDEFG\n'.
uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE)

puts "peek before anything: #{uart.peek}"

arena(256) do
  line = uart.gets
  puts "gets took #{line.size} bytes"
end

puts "still waiting: #{uart.bytes_available}"
puts "next byte: #{uart.peek}"

uart.clear_rx_buffer
puts "after clearing: #{uart.bytes_available}"
