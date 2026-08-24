# The wave itself: TIM2's compare output drives PA5 — the LD2 wire — so the LED
# tester can hold the duty cycle to the asked-for ratio. The program may end; the
# counter keeps running, which is the point of it being hardware.
pwm = PWM.new(5, frequency: 50, duty: 30)
puts "waving"
