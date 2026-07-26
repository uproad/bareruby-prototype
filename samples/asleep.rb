led = GPIO.new(25, GPIO::OUT)
pulse = GPIO.new(16, GPIO::OUT)
adc = ADC.new(26)

edge = 0
while edge < 1000
  pulse.write(1)
  asleep_us(50)
  pulse.write(0)
  asleep_us(50)
  edge = edge + 1
end

sum = 0
count = 0
while count < 500
  sum = sum + adc.read_raw
  count = count + 1
  asleep_ms(10)
end

state = 0
loop do
  state = 1 - state
  led.write(state)
  spin = 0
  while spin < sum
    spin = spin + 1
  end
  asleep(1)
end
