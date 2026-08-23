uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE)

uart.irq(UART::RX_RECEIVE) do |port, event|
  port.puts "irq #{event}: #{port.getbyte}"
end

sleep_ms(10)
puts "done"
