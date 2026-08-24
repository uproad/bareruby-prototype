# off must return a lit LED to dark — under active_high, ODR bit 5 back to zero.
led = OnboardLED.new
led.on
led.off
puts "off"
