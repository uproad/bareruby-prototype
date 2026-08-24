# A wait is where the notification handler gets to run, and interrupt: false says it
# may not. The harness injects a byte during the first wait: it is not delivered
# there, it is not lost, and the next default wait is where the handler speaks.
uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE)

uart.irq(UART::RX_RECEIVE) do |port, event|
  byte = port.getbyte
  while byte >= 0
    puts "handler took #{byte}"
    byte = port.getbyte
  end
end

puts "first"
asleep_ms(400, interrupt: false)
puts "second"
asleep_ms(400)
puts "third"
