uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE)
i2c = I2C.new(unit: 1, frequency: 100_000)

arena(128) do
  two = i2c.read(0x76, 2, 0x00)
  uart.write two
  size = two.size
  uart.write "/#{size}/"
  four = i2c.read(0x76, 4, 0x00)
  uart.write four
  size = four.size
  uart.write "/#{size}"
end
