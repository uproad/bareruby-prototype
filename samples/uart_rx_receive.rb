# The receive notification hands the handler the peripheral it is about and which event
# fired, and nothing else. What a line is, and whether one has arrived, is the program's
# business now rather than four bindings'. Feed it 'ON\n' or 'OFF\n'.
led = OnboardLED.new
led.off

uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE)

uart.irq(UART::RX_RECEIVE) do |port, event|
  indicator = OnboardLED.new
  byte = port.read_byte
  while byte >= 0
    indicator.on if byte == 79   # O
    indicator.off if byte == 70  # F
    byte = port.read_byte
  end
end

puts "listening"

# A bounded wait rather than a loop, so that running this on the host ends.
3.times do
  sleep_ms(10)
end

puts "done"
