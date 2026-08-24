# 50 Hz on the microsecond tick: PSC holds the 84 MHz -> 1 MHz division, ARR the
# 20000-tick period, and CR1 the running counter. period_us(20_000) asks for the
# same thing and must leave the same registers.
pwm = PWM.new(5, frequency: 50)
pwm.period_us(20_000)
puts "set"
