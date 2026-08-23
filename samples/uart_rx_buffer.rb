# How deep the receive queue is, is the program's to choose. It is settled while compiling
# because the storage is static, so the number has to be known where the storage is
# declared rather than handed to the constructor as the rest of the frame is. Feed it more
# than 256 bytes: with the queue this asks for, none of them are dropped.
uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE, rx_buffer_size: 1024)

puts "waiting: #{uart.bytes_available}"

taken = 0
byte = uart.getbyte
while byte >= 0
  taken += 1
  byte = uart.getbyte
end

puts "took #{taken} bytes"
