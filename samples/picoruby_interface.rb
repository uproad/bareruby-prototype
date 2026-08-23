# The interfaces PicoRuby publishes are the ones a program written for PicoRuby is written
# against, so they are the ones this compiler has to answer to. Four calls here were
# spelled differently until now: the bus took its unit by position rather than by name,
# the serial line broke the wire and fetched a byte under names of its own, and the pin
# registered an interrupt under a name no other implementation uses. Every one of them
# meant that source which runs elsewhere would not compile here, which is the whole of
# what compatibility is.
i2c = I2C.new(unit: 1, frequency: 400_000)

uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE)
uart.break(1)

button = GPIO.new(15, GPIO::IN | GPIO::PULL_UP)

button.irq(GPIO::EDGE_FALL) do
  led = OnboardLED.new
  led.on
end

arena(256) do
  reading = i2c.read(0x48, 2, 0x00)
  puts "read #{reading.size} bytes"
end

puts "first byte #{uart.getbyte}"
