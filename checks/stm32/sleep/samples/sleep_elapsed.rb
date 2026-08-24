# Virtual time is deterministic, so the elapsed milliseconds of a sleep are one exact
# number — the +1 tick the HAL's polling costs included.
before = ticks_ms
sleep_ms(100)
mid = ticks_ms
sleep_ms(1)
after = ticks_ms
puts mid - before
puts after - mid
