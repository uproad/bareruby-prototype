# A two-wire bus, as the language offers it.
class I2C
  native_ivar id: :Int32, frequency: :Int32

  sig id: :Int32, frequency: :Int32, returns: :Nil
  def initialize(id, frequency: 100_000); end

  # One call in Ruby is one transaction on the wire, so whatever the program hands over —
  # integers, static strings, arrays, strings from a region — reaches the bus as one
  # contiguous sequence. Flattening them is the type's business rather than this class's,
  # which is why the sig names one parameter where C receives a pointer and a length.
  sig address: :Int32, outputs: :byte_sequence, returns: :Int32
  def write(address, *outputs); end

  sig address: :Int32, length: :Int32, outputs: :byte_sequence, returns: :"Arena::String"
  def read(address, length, *outputs); end
end
