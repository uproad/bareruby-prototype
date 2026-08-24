# The microsecond tick makes a pulse width the compare value itself: 1500us is CCR
# 1500. PC7 exercises the other table row — TIM3, channel 2, AF2.
pwm = PWM.new(39, frequency: 50)
pwm.pulse_width_us(1500)
puts "set"
