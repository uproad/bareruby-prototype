# PA5 as an output: write answers 0, and the driven state reads back through IDR —
# HAL's ReadPin — with the predicates agreeing with read.
led = GPIO.new(5, GPIO::OUT)
puts led.write(1)
puts led.read
puts led.high?
led.write(0)
puts led.read
puts led.low?
