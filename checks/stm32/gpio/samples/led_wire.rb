# Drive PA5 high and stop. The harness then reads the LED model wired to PA5 and the
# port A registers — the write must reach the connection, not just the ODR bit.
led = GPIO.new(5, GPIO::OUT)
led.write(1)
puts "on"
