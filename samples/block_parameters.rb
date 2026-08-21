# A block takes what it is handed, and the two do not have to be the same length. A value
# nobody named is dropped, and a name nothing was handed to is nil — which is what Ruby
# does in both directions. The rule is the same wherever the block is run from.
3.times do
  puts "tick"
end

3.times do |turn, spare|
  puts "turn #{turn}, spare is nil: #{spare.nil?}, and it renders as '#{spare}'"
end

uart = UART.new(0, baud: 115_200, parity: UART::NONE)

# The binding hands this one a line. Not looking at it is allowed; the handler still has
# the shape the binding calls it through.
uart.on_line do
  led = OnboardLED.new
  led.on
end

button = GPIO.new(14, GPIO::IN)

# This one is handed nothing, so the name it asked for is nil.
button.on_interrupt(edge: GPIO::EDGE_FALL) do |pin|
  other = OnboardLED.new
  other.off
end
