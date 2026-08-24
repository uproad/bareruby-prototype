# sleep_ms answers the milliseconds it was given, whatever they were — only the wait
# is clamped at zero, which the ticks_ms difference around the negative call shows.
puts sleep_ms(100)
puts sleep_ms(0)
before = ticks_ms
puts sleep_ms(-5)
puts ticks_ms - before
