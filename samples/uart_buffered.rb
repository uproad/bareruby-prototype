# Arduino HardwareSerial-style buffered receive: available/read_byte/peek backed by the
# interrupt-fed ring, and ticks_ms, composed into the timeout line read the framework
# calls readBytesUntil. No callback is registered; the main loop owns the bytes.
uart = UART.new(0, baud: 115_200, parity: UART::NONE, stop_bits: 1)

puts "buffered receive: reading until LF or 2000 ms"

if uart.bytes_available > 0
  puts "first byte will be #{uart.peek}"
end

deadline = ticks_ms + 2000
count = 0
byte = 0
while byte != 10 && (deadline - ticks_ms) > 0
  if uart.bytes_available > 0
    byte = uart.read_byte
    count += 1
  else
    sleep_ms(10)
  end
end

if byte == 10
  puts "line of #{count} bytes (LF included)"
else
  puts "timeout after #{count} bytes"
end
