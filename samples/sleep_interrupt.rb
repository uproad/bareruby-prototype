# A wait is where a notification handler gets to run, and interrupt: false says it may
# not. Send "ON" and "OFF", each followed by Enter.
uart = UART.new(0, baud: 115200, parity: UART::NONE)

uart.irq(UART::RX_RECEIVE) do |port, event|
  byte = port.read_byte
  while byte >= 0
    puts "handler took #{byte}"
    byte = port.read_byte
  end
end

puts "not listening"
asleep_ms(10, interrupt: false)

puts "listening"
asleep_ms(10)

puts "done"
