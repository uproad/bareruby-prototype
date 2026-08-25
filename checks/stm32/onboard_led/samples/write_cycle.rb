# write(1)/write(0) fold onto the same board write as on/off, and the final write(2)
# pins the zero/non-zero contract — any non-zero lights. The harness reads the LED
# model mid-run, inside the first lit stretch, and again at the end.
led = OnboardLED.new
led.write(1)
sleep_ms(500)
led.write(0)
sleep_ms(300)
led.write(2)
puts "cycled"
