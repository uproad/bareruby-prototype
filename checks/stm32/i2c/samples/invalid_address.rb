i2c = I2C.new(unit: 1, frequency: 100_000)
puts "before"

arena(64) do
  i2c.write(0x80, 0x00)
end

puts "after"
