# PA8 is bonded out but carries no ADC channel, so it sits on no row of the board's
# table — a different refusal from the range check, through the table's default case,
# and nothing after the marker is ever said.
puts "before"
bad = ADC.new(8)
puts "after"
