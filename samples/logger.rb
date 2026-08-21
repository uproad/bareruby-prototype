uart = UART.new(unit: 0, baudrate: 115200, parity: UART::NONE)
button = GPIO.new(14, GPIO::IN | GPIO::PULL_UP)

uart.puts("logger ready")

count = 0
loop do
  if button.read == 0
    count = count + 1
    uart.puts("pressed: #{count}")
  end
  sleep_ms(100)
end
