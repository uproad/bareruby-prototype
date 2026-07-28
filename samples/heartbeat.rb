led = OnboardLED.new

loop do
  led.on
  sleep_ms(100)
  led.off
  sleep_ms(900)
end
