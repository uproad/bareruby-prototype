# sleep counts in seconds and answers them; the conversion to milliseconds is what
# the elapsed difference pins.
before = ticks_ms
puts sleep(1)
puts ticks_ms - before
