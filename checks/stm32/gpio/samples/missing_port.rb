# Pin 64 is PE0, and the F446RE package does not bond port E out: the adapter's port
# table answers NULL and the binding faults. A different refusal path than the range
# check, so both are pinned.
puts "before"
bad = GPIO.new(64, GPIO::OUT)
puts "after"
