i2c = I2C.new(unit: 1, frequency: 100_000)

arena(4096) do
  chunk = ::Array.new(16, 0)
  total = 0
  base = 0
  while base < 256
    offset = 0
    while offset < 16
      chunk[offset] = base + offset
      offset += 1
    end
    total += i2c.write(0x76, 0x40, chunk)
    base += 16
  end

  score = i2c.read(0x76, 7, 0x41)
  puts score
  puts score.size
  puts total
end
