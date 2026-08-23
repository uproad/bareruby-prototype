uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE)
i2c = I2C.new(unit: 1, frequency: 100_000)

arena(128) do
  answer = i2c.read(0x76, 1, 0x00)
  uart.write answer
  size = answer.size
  uart.write "/#{size}"
end
