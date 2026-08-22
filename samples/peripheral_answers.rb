# **What a call answers is as much its interface as what it takes.** A program written for
# the same classes elsewhere reads these values back, chains on them, or prints them, and a
# call that answers nothing where the class it names answers something is a call that
# source cannot be written against.
#
# Fractions are answered as Fixed rather than Float, which is what every fraction is here.
led = GPIO.new(25, GPIO::OUT)
puts "write answered #{led.write(1)}"

pwm = PWM.new(15, frequency: 50, duty: 30)
puts "frequency #{pwm.frequency(440)}"
puts "period 2273us is #{pwm.period_us(2273)} Hz"
puts "duty #{pwm.duty(50)}"
puts "1500us of that period is #{pwm.pulse_width_us(1500)}%"

# The control calls answer the line itself, so they chain.
uart = UART.new(unit: 0, baudrate: 9600)
uart.flush.puts "chained"
uart.setmode(baudrate: 19_200).clear_tx_buffer.break(1).clear_rx_buffer

puts "slept #{sleep_ms(1)} ms"
