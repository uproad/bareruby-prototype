i2c = I2C.new(unit: 1, frequency: 100_000)

arena(64) do
  puts i2c.write(0x76, 0x00, 0x10, 0x20)
end
