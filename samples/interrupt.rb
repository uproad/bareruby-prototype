button = GPIO.new(15, GPIO::IN | GPIO::PULL_UP)

button.on_interrupt(edge: GPIO::EDGE_FALL) do
  led = GPIO.new(25, GPIO::OUT)
  led.write(1)
end
