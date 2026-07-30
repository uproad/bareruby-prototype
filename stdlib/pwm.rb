# A pulse-width modulated output, as the language offers it.
class PWM
  native_ivar pin: :Int32, slice: :Int32, frequency: :Int32

  sig pin: :Int32, frequency: :Int32, duty: :Int32, returns: :Nil
  def initialize(pin, frequency: 0, duty: 0); end

  sig frequency: :Int32, returns: :Nil
  def frequency(frequency); end

  sig period_us: :Int32, returns: :Nil
  def period_us(period_us); end

  sig duty: :Int32, returns: :Nil
  def duty(duty); end

  sig pulse_width_us: :Int32, returns: :Nil
  def pulse_width_us(pulse_width_us); end
end
