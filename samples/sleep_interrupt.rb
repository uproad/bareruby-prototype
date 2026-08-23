# A wait is where a notification handler gets to run, and interrupt: false says it may
# not. Send "ON" and "OFF", each followed by Enter.
uart = UART.new(unit: 0, baudrate: 115200, parity: UART::NONE)

uart.irq(UART::RX_RECEIVE) do |port, event|
  byte = port.getbyte
  while byte >= 0
    puts "handler took #{byte}"
    byte = port.getbyte
  end
end

puts "not listening"
asleep_ms(10, interrupt: false)

puts "listening"
asleep_ms(10)

puts "done"
