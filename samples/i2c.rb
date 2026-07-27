i2c = I2C.new(1, frequency: 400_000)

arena(size: 256) do |a|
  command = a.string("\x30")
  command << "\xa2"
  values = [0x10, 0x20]

  puts i2c.write(0x45, 0x01, values, "\x40", command)

  reading = i2c.read(0x48, 2, 0x00)
  puts reading
  puts reading.size
end
