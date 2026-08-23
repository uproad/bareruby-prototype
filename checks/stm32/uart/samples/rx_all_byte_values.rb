uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE)

i = 0
errors = 0
while i < 256
  byte = uart.getbyte
  if byte >= 0
    errors += 1 if byte != i
    i += 1
  end
end

puts i
puts errors
puts uart.bytes_available
