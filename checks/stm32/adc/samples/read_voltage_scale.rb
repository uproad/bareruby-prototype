# One known voltage — 1650 mV, raw 0x7FF — read all three ways: the raw value, and
# the two spellings of the voltage, which land on the same call and must say the same
# Fixed. The scale is the 3.3 V full scale the pico_sdk binding set the precedent for.
adc = ADC.new(0)
puts "raw #{adc.read_raw}"
puts "read #{adc.read}"
puts "voltage #{adc.read_voltage}"
