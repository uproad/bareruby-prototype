# A body that overruns the interval: the overdue asleep returns without waiting and
# re-anchors the mark at now, so the next lap is back on cadence rather than paying
# the debt with a string of instant returns.
asleep_ms(10)
prev = ticks_ms
sleep_ms(150)
asleep_ms(100)
now = ticks_ms
puts now - prev
prev = now
sleep_ms(20)
asleep_ms(100)
puts ticks_ms - prev
