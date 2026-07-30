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

  # One implementation per kind of machine. Which one a build takes is the target's answer,
  # and a program says nothing about it.
  native_variant :hosted do
    body :initialize, <<~'CPP'
      self->pin = pin;
      self->params = params;
      fprintf(stderr, "gpio_init(pin=%d, params=%d)\n", (int)pin, (int)params);
    CPP

    body :write, <<~'CPP'
      fprintf(stderr, "gpio_write(pin=%d, value=%d)\n", (int)self->pin, (int)value);
    CPP

    body :read, <<~'CPP'
      fprintf(stderr, "gpio_read(pin=%d) -> 0\n", (int)self->pin);
      return 0;
    CPP

    body :high?, <<~'CPP'
      fprintf(stderr, "gpio_high(pin=%d) -> false\n", (int)self->pin);
      return false;
    CPP

    body :low?, <<~'CPP'
      fprintf(stderr, "gpio_low(pin=%d) -> true\n", (int)self->pin);
      return true;
    CPP

    # Nothing interrupts on the machine doing the compiling, so registering runs the handler
    # once and that is the whole of it.
    body :on_interrupt, <<~'CPP'
      fprintf(stderr, "gpio_on_interrupt(pin=%d, events=%d)\n", (int)self->pin, (int)events);
      handler();
    CPP
  end

  native_variant :freestanding do
    # The SDK hands a callback the pin and the events, and a block takes neither, so
    # something has to stand between them. It belongs here rather than with a method
    # because it is this implementation's own, and the other one needs nothing like it.
    prelude <<~'CPP'
      static bareruby_interrupt_handler_t bareruby_gpio_interrupt_handler;

      static void bareruby_gpio_interrupt_callback(uint gpio, uint32_t events) {
          (void)gpio;
          (void)events;
          bareruby_gpio_interrupt_handler();
      }
    CPP

    body :initialize, <<~'CPP'
      self->pin = pin;
      self->params = params;
      gpio_init((uint)pin);
      gpio_set_dir((uint)pin, (params & 2) ? GPIO_OUT : GPIO_IN);
      if (params & 4) {
          gpio_set_input_enabled((uint)pin, false);
      }
      if (params & 8) {
          gpio_pull_up((uint)pin);
      } else if (params & 16) {
          gpio_pull_down((uint)pin);
      } else {
          gpio_disable_pulls((uint)pin);
      }
    CPP

    body :write, <<~'CPP'
      gpio_put((uint)self->pin, value != 0);
    CPP

    body :read, <<~'CPP'
      return gpio_get((uint)self->pin) ? 1 : 0;
    CPP

    body :high?, <<~'CPP'
      return gpio_get((uint)self->pin);
    CPP

    body :low?, <<~'CPP'
      return !gpio_get((uint)self->pin);
    CPP

    body :on_interrupt, <<~'CPP'
      bareruby_gpio_interrupt_handler = handler;
      gpio_set_irq_enabled_with_callback(
          (uint)self->pin, (uint32_t)events, true, bareruby_gpio_interrupt_callback);
    CPP
  end
end
