# An analogue input, as the language offers it.
class ADC
  native_ivar pin: :Int32, channel: :Int32

  sig pin: :Int32, returns: :Nil
  def initialize(pin); end

  # The standard guideline returns a float from read_voltage, but this language has no
  # floats: Fixed is the fractional type, and Q16.16 resolves to 1/65536 V — finer than the
  # least significant bit of a 12-bit converter. read is the same reading under the name a
  # program is likelier to reach for, so both are one function and the second says which.
  sig returns: :Fixed
  def read; end

  sig function: :bareruby_adc_read, returns: :Fixed
  def read_voltage; end

  sig returns: :Int32
  def read_raw; end
end
