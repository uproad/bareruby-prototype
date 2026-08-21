# A peripheral class is not only a mapping onto C functions. can_read_line is written in
# Ruby, once, in the gem that declares UART, and a program opens the same class to add one
# of its own. Both reach the C vocabulary the hardware needs and nothing more.
class UART
  def drop_waiting
    dropped = 0
    while can_read_line
      read_byte
      dropped += 1
    end
    dropped
  end
end

uart = UART.new(unit: 0, baudrate: 115_200, parity: UART::NONE)

puts "waiting: #{uart.can_read_line}"
puts "dropped #{uart.drop_waiting} bytes"
puts "waiting: #{uart.can_read_line}"
