# The voltages whose raw values sit on byte boundaries — 255, 256 and 3840, the
# 0x0FF/0x100 step and 0xF00 — the same thought the UART and I2C suites fix with
# 0x00 and 0xFF: the bytes likeliest to be mangled, held to exact answers.
adc = ADC.new(0)
puts "raw #{adc.read_raw}"
sleep_ms(500)
puts "raw #{adc.read_raw}"
sleep_ms(500)
puts "raw #{adc.read_raw}"
