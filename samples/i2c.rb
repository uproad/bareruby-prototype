i2c = I2C.new(unit: 1, frequency: 400_000)

arena(256) do
  command = Arena::String.new("\x30")
  command << "\xa2"
  values = ::Array.new(2, 0x10)

  puts i2c.write(0x45, 0x01, values, "\x40", command)

  reading = i2c.read(0x48, 2, 0x00)
  puts reading
  puts reading.size
  puts reading.getbyte(0)
  puts reading.getbyte(-1)
end
