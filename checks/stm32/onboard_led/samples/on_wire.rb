# The program never says a pin number: the manifest's led (PA5, the board's LD2) is
# the binding's answer. The harness reads the LED model and port A's registers after.
led = OnboardLED.new
led.on
puts "on"
