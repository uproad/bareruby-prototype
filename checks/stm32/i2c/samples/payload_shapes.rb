uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE)
i2c = I2C.new(unit: 1, frequency: 100_000)

arena(256) do
  command = Arena::String.new("\x10")
  command << "\x11"
  values = ::Array.new(2, 0x22)

  wrote = i2c.write(0x76, 0x02, 0x01, values, "\x33", command)
  uart.write "#{wrote}/"

  answer = i2c.read(0x76, 6, 0x02)
  uart.write answer
end
