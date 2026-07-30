# A serial port, as the language offers it.
class UART
  NONE = 0
  EVEN = 1
  ODD = 2
  RTSCTS = 4

  native_ivar id: :Int32, baud: :Int32, parity: :Int32

  # The keywords and what they fall back to are Ruby's to say, so the def says them and the
  # sig only gives the types.
  sig id: :Int32, baud: :Int32, parity: :Int32, returns: :Nil
  def initialize(id, baud: 115_200, parity: 0); end

  # Two sigs, one def. An interpolation is a type like any other, and the version that
  # takes one is variadic in C — so writing text and writing a rendering are the same
  # method in Ruby and two functions underneath, chosen by what the argument is.
  # The variadic version answers nothing: what it wrote is not counted, so writing a
  # rendering hands back nil where writing text hands back the byte count. The two methods
  # share that one function, which is why both name it.
  sig value: :String, returns: :Int32
  sig value: :Interpolation, function: :bareruby_uart_printf, returns: :Nil
  def write(value); end

  sig value: :String, returns: :Nil
  sig value: :Interpolation, function: :bareruby_uart_printf, returns: :Nil
  def puts(value); end

  # A received string is variable-length, so it comes from the region that is current. No
  # region appears here: a program cannot name one, and the binding reads the one word that
  # says which is open.
  sig length: :Int32, returns: :"Arena::String"
  def read(length); end

  sig returns: :"Arena::String"
  def gets; end

  sig returns: :Int32
  def bytes_available; end

  sig returns: :Bool
  def can_read_line; end

  sig returns: :Nil
  def flush; end

  sig returns: :Nil
  def clear_rx_buffer; end

  sig returns: :Nil
  def clear_tx_buffer; end
end
