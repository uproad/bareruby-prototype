led = GPIO.new(25, GPIO::OUT)

loop do
  led.write(1)
  sleep_ms(500)
  led.write(0)
  sleep_ms(500)
end
