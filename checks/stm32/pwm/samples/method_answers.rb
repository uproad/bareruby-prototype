# What a call answers is declared arithmetic, board-independent — pinning it here
# proves the calls build and answer the same on the STM32 as everywhere else.
pwm = PWM.new(15, frequency: 50, duty: 30)
puts pwm.frequency(50)
puts pwm.period_us(20_000)
puts pwm.duty(50)
puts pwm.pulse_width_us(1500)
