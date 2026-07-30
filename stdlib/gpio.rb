# One pin of the microcontroller, as the language offers it.
#
# This file is the whole declaration of the class: what a program may say to it, what
# state an instance carries, and — once the second stage asks — what C++ stands behind
# each method. The compiler reads this file rather than running it, so a pure Ruby method
# body here is source for the passes like any other, not something that executes while
# compiling.
class GPIO
  # One-hot, so that a direction and a pull combine with | the way the standard guideline
  # spells them. Zero is not a value: with it, IN and "no direction given" would be the
  # same number, and a rule that requires a direction could not be stated.
  IN = 1
  OUT = 2
  HIGH_Z = 4
  PULL_UP = 8
  PULL_DOWN = 16
  OPEN_DRAIN = 32
  EDGE_FALL = 4

  # The state an instance carries. Two plain numbers, so the compiler generates the struct
  # and the C++ reads self->pin. The types are declared because only C++ assigns them:
  # a class written in Ruby settles its instance variables from what initialize stores,
  # and there is no such assignment to read here.
  native_ivar pin: :Int32, params: :Int32

  # A sig marks the def that follows as native: its body is not here but with the
  # implementations. The C function name is derived from the class and the method, so
  # `high?` reaches `bareruby_gpio_high` and nothing spells that name twice.
  sig pin: :Int32, params: :Int32, returns: :Nil
  def initialize(pin, params); end

  sig value: :Int32, returns: :Nil
  def write(value); end

  sig returns: :Int32
  def read; end

  sig returns: :Bool
  def high?; end

  sig returns: :Bool
  def low?; end

  # The block becomes a C function with neither arguments nor a return, and its address is
  # what the binding receives. Ruby's own `&handler` says that much; what the sig adds is
  # the context the block runs in, because an interrupt handler may not touch a region and
  # the compiler has to know which blocks to hold to that rule.
  sig events: :Int32, block: :realtime, returns: :Nil
  def on_interrupt(events, &handler); end
end
