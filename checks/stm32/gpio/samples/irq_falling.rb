# A falling edge on PC13 must reach the handler through EXTI and the NVIC. The handler
# runs in the realtime context and only raises PA5 (making its own handle, as
# samples/interrupt.rb does); the main loop does the observing and the talking, so the
# marker order proves the handler ran only after the press.
flag = GPIO.new(5, GPIO::OUT)
flag.write(0)

button = GPIO.new(45, GPIO::IN | GPIO::PULL_UP)
button.irq(GPIO::EDGE_FALL) do
  led = GPIO.new(5, GPIO::OUT)
  led.write(1)
end

puts "waiting"
while flag.low?
  sleep_ms(1)
end
puts "interrupt"
