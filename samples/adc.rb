sensor = ADC.new(26)
led = PWM.new(6, frequency: 100000, duty: 0)

loop do
  level = sensor.read / 3.3
  led.duty((level * 100).to_i32)
  sleep_ms(10)
end
