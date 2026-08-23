uart = UART.new(unit: 0, baudrate: 115_200, data_bits: 9, parity: UART::NONE)

written = uart.write "AB"

uart.setmode(data_bits: 8)
uart.puts "written #{written}"
