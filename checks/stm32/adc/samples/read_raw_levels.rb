# A0 (PA0 = ADC1_IN0) read three times while the harness moves the channel's given
# voltage between two slices of the run: 0 mV, the full 3300 mV, then the 1650 mV
# halfway point — the 12-bit range's both ends and the middle, arriving as raw values.
adc = ADC.new(0)
puts "raw #{adc.read_raw}"
sleep_ms(500)
puts "raw #{adc.read_raw}"
sleep_ms(500)
puts "raw #{adc.read_raw}"
