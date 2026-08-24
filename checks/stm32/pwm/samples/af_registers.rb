# The pin side of PWM: PA5 into alternate function 1, TIM2's channel, with the reset
# value and the USART2 wiring preserved around it.
pwm = PWM.new(5, frequency: 50, duty: 30)
puts "wired"
