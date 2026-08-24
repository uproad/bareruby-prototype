# PC13 is the board's B1 user button: high at rest, low while pressed. The harness
# presses the emulated button mid-run; the program reports the level on both sides.
button = GPIO.new(45, GPIO::IN | GPIO::PULL_UP)
puts button.read
while button.high?
  sleep_ms(1)
end
puts button.read
