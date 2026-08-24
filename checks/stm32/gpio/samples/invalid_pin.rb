# A pin number outside the range is refused by the pin-range check with
# bareruby_board_fault, so nothing after the marker is ever said.
puts "before"
bad = GPIO.new(-1, GPIO::OUT)
puts "after"
