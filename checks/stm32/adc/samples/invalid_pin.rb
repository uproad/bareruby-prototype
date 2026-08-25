# A pin number outside any port is refused with bareruby_board_fault at the ADC's
# own entrance, so nothing after the marker is ever said.
puts "before"
bad = ADC.new(-1)
puts "after"
