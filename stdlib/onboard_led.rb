# The LED on the board, as the language offers it.
#
# It is a class of its own rather than a GPIO with a known pin, because on a board that has
# one it is frequently not a GPIO at all — a wireless board drives its LED through the radio,
# and the pin where a plain board's LED sits is that radio's select line instead. Sharing
# GPIO's interface would only hide that. Which board the program is being built for decides
# how the binding reaches it, so a program that blinks says nothing about the board it will
# run on.
class OnboardLED
  # Where the LED is and how it is driven belong to the board, which the binding already
  # knows, so there is nothing here for the program to carry. The state exists so that an
  # instance has storage like every other peripheral.
  native_ivar state: :Int32

  sig returns: :Nil
  def initialize; end

  sig value: :Int32, returns: :Nil
  def write(value); end

  sig returns: :Nil
  def on; end

  sig returns: :Nil
  def off; end
end
