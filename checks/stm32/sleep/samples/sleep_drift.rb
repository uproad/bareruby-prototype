# sleep counts from the moment it is called, so a lap is the body plus the whole wait
# — the drift asleep_cadence is the counterpart to. The body is itself a sleep so the
# lap stays one deterministic number.
prev = ticks_ms
lap = 0
while lap < 3
  sleep_ms(20)
  sleep_ms(100)
  now = ticks_ms
  puts now - prev
  prev = now
  lap += 1
end
