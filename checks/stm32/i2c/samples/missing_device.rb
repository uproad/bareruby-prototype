i2c = I2C.new(unit: 1, frequency: 100_000)
puts "before"

arena(64) do
  puts i2c.write(0x50, 0x00)
end

puts "after"
