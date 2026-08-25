# A quarter of a 20000-tick period is compare value 5000, with the channel held in
# PWM mode 1 and enabled.
pwm = PWM.new(5, frequency: 50, duty: 25)
puts "set"
