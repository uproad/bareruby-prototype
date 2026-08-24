# asleep counts from the period mark, so the body's 20ms comes out of the wait and
# the lap holds at the interval. The throwaway asleep first anchors the mark, which
# starts at boot time zero.
asleep_ms(10)
prev = ticks_ms
lap = 0
while lap < 3
  sleep_ms(20)
  asleep_ms(100)
  now = ticks_ms
  puts now - prev
  prev = now
  lap += 1
end
