i2c = I2C.new(unit: 1, frequency: 100_000)

arena(128) do
  i2c.write(0x76, 0x00, "AB")
  answer = i2c.read(0x76, 2, 0x00)
  puts answer
  puts answer.size
end
