uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE)

uart.irq(UART::RX_RECEIVE) do |port, event|
  byte = port.getbyte
  if byte == 65
    port.clear_rx_buffer
    puts "cleared #{port.bytes_available}"
  else
    puts byte if byte >= 0
  end
end

sleep_ms 40
puts "done"
