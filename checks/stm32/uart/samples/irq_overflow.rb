uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE, rx_buffer_size: 4)

uart.irq(UART::RX_RECEIVE) do |port, event|
  byte = port.getbyte
  puts byte if byte >= 0
end

sleep_ms 20
puts "done"
