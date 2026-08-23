uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE)

4.times do
  puts uart.getbyte
end
