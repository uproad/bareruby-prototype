i2c = I2C.new(unit: 1, frequency: 100_000)

# getbyte is how a reading comes apart into values: the register pair at 0x04 answers
# 0xF4 and 0xF5, a negative index counts from the end as Ruby's does, and the word the
# two assemble is what a sensor driver builds from a pair. Past the end is thrown, and
# answering it here crosses the same unwind tables a raise already crosses on this
# board.
arena(128) do
  reading = i2c.read(0x76, 2, 0x04)
  hi = reading.getbyte(0)
  lo = reading.getbyte(-1)
  puts "#{hi}/#{lo}/#{(hi << 8) | lo}"
  begin
    puts reading.getbyte(9)
  rescue
    puts "past the end"
  end
end
