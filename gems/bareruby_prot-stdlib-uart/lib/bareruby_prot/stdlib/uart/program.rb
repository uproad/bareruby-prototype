# The part of UART that is not the hardware's. It is compiled into the program that uses
# the class, so it is written in the language that program is written in, and it reaches
# the same C vocabulary a program does. Nothing here is paid for unless it is called.
#
# **What the hardware knows is bytes.** Filling the queue from the line, taking one byte
# off it, looking at the next one and asking how deep it is — that is the whole of what a
# board has to answer. A line is not a thing a wire has, so where one ends is decided
# here, once, rather than in every binding.
class UART
  # Whether a read would find something waiting. Every board answered this from C, and
  # every board answered it the same way, which is how four copies of one sentence came
  # to exist.
  def can_read_line
    bytes_available > 0
  end

  # Everything up to and including what a line ends with here. A wire that is saying
  # nothing is waited for, because a wire that is saying nothing is not a wire that has
  # finished.
  def gets
    line = Arena::String.new("")
    ending = line_terminator
    byte = 0
    while byte != ending
      byte = read_byte
      line << byte if byte >= 0
    end
    line
  end

  # The next length bytes, waited for the same way.
  def read(length)
    taken = Arena::String.new("")
    while taken.size < length
      byte = read_byte
      taken << byte if byte >= 0
    end
    taken
  end
end
