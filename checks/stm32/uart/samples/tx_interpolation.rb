uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE)

value = 5
uart.write "w#{value}"
uart.puts "p#{value}"
big = 3_000_000_000
uart.write "big=#{big}"
