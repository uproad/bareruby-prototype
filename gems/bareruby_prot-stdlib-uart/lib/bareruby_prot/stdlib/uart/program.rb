# The part of UART that is not the hardware's. It is compiled into the program that uses
# the class, so it is written in the language that program is written in, and it reaches
# the same C vocabulary a program does. Nothing here is paid for unless it is called.
class UART
  # Whether a read would find something waiting. Every board answered this from C, and
  # every board answered it the same way, which is how four copies of one sentence came
  # to exist.
  def can_read_line
    bytes_available > 0
  end
end
