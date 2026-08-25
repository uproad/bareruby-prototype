# The ends of the duty range: 0 is no pulse, 100 is the whole period — as a compare
# value, one past ARR, which PWM mode 1 holds constantly active.
pwm = PWM.new(5, frequency: 50)
puts pwm.duty(0)
puts pwm.duty(100)
