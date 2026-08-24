# PA0 is bonded out but on no row of this board's PWM table, so the board answers
# with a fault and nothing after the marker is ever said.
puts "before"
pwm = PWM.new(0, frequency: 50)
puts "after"
