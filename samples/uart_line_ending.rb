# What the line was opened with can be changed afterwards, and setmode says nothing about
# the parts it does not name. What a line ends with is the class's to know and the
# program's to choose: it reaches both what puts puts after the text and what gets reads
# up to. Feed it 'abc' followed by a carriage return and nothing else.
uart = UART.new(unit: 0, baudrate: 9600, parity: UART::EVEN)

uart.puts "opened at #{uart.baudrate}"

uart.setmode(baudrate: 115_200)
uart.puts "now at #{uart.baudrate}"

uart.line_ending = "\r\n"
uart.puts "this line ends the other way"

uart.line_ending = "\r"

arena(256) do
  line = uart.gets
  puts "read #{line.size} bytes, with no newline in sight"
end
