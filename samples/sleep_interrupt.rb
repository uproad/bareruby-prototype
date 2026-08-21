# A wait is where a notification handler gets to run, and interrupt: false says it may
# not. Send "ON" and "OFF", each followed by Enter.
uart = UART.new(0, baud: 115200, parity: UART::NONE)

uart.on_line do |line|
  if line == "ON"
    puts "handler saw ON"
  elsif line == "OFF"
    puts "handler saw OFF"
  end
end

puts "not listening"
asleep_ms(10, interrupt: false)

puts "listening"
asleep_ms(10)

puts "done"
