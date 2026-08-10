# UART receive interrupt callback test.
#
# Send "ON" or "OFF" followed by Enter over UART0.
led = OnboardLED.new
led.off

uart = UART.new(0, baud: 115200, parity: UART::NONE)

uart.on_line do |line|
  interrupt_led = OnboardLED.new
  if line == "ON"
    interrupt_led.on
  elsif line == "OFF"
    interrupt_led.off
  end
end

puts "UART interrupt test: send ON or OFF, followed by Enter"

loop do
  sleep_ms(1000)
end
