# The recorded fault of asleep_us: it delays for its promise but never moves the
# period mark and never delivers. So the following asleep_ms finds its deadline long
# past, returns at once — and, being overdue, never enters the drain loop either, so
# the byte the harness injected during the microsecond delay stays undelivered to the
# end of the program. The expectation changes when asleep_us joins the other two.
uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE)

uart.irq(UART::RX_RECEIVE) do |port, event|
  byte = port.getbyte
  while byte >= 0
    puts "handler took #{byte}"
    byte = port.getbyte
  end
end

asleep_ms(10)
before = ticks_ms
asleep_us(500_000)
mid = ticks_ms
puts mid - before
asleep_ms(10)
puts ticks_ms - mid
puts "end"
