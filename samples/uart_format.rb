# UART frame format and the two control calls the standard guideline defines.
#
# 7E1 at 9600: seven data bits, even parity, one stop bit. The format a program
# asks for is the binding's to produce or refuse -- it is never quietly replaced,
# because a wrong frame is rubbish on the wire and there is nowhere safe to fall.
uart = UART.new(unit: 0, baudrate: 9600, parity: UART::EVEN, data_bits: 7, stop_bits: 1)

uart.puts "7E1 ready"
puts "pending #{uart.bytes_to_write}"

uart.flush
puts "pending #{uart.bytes_to_write}"

uart.send_break(1)
puts "break sent"
