uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE)

uart.bytes_available
sleep_ms 100

count = uart.bytes_available
errors = 0
i = 0
while i < count
  errors += 1 if uart.getbyte != i % 251 + 1
  i += 1
end

puts count
puts errors
puts uart.getbyte
