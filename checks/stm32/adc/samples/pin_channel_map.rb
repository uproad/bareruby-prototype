# Every analog pin the board's table carries — the Arduino header's A0 through A5 —
# each channel held at its own voltage, so a pin landing on the wrong channel answers
# the wrong value. The serial pin numbers cross ports: 0/1/4 are PA0/PA1/PA4, 16 is
# PB0, 33 and 32 are PC1 and PC0.
a0 = ADC.new(0)
a1 = ADC.new(1)
a2 = ADC.new(4)
a3 = ADC.new(16)
a4 = ADC.new(33)
a5 = ADC.new(32)
puts "a0 #{a0.read_raw}"
puts "a1 #{a1.read_raw}"
puts "a2 #{a2.read_raw}"
puts "a3 #{a3.read_raw}"
puts "a4 #{a4.read_raw}"
puts "a5 #{a5.read_raw}"
