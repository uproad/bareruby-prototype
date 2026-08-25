# The even blink: the harness measures the LED model's duty cycle over virtual time
# with Renode's LED tester, which is what makes 0.5 an assertion instead of a reading.
led = OnboardLED.new
puts "blinking"
loop do
  led.on
  sleep_ms(500)
  led.off
  sleep_ms(500)
end
