# frozen_string_literal: true

require "bareruby_prot/peripheral"

# A serial line as a class a program may name. Everything the compiler learns about it is
# here: what may be said to it, what those calls lower to, what the generated C++ must
# declare, and which translation units a binding has to supply once they are reached.
#
# **Sending and receiving are separate units.** A program that only writes never links the
# receive path, which pulls in the arena to answer variable-length strings. That split
# already existed as a rule the compiler carried; it is stated here now, by the class it
# belongs to.
module BareRubyProt
  Peripheral.register(
    :UART,
struct: :bareruby_uart_t,
      # RX_RECEIVE is which event a handler is registered for. There is one of them, and
      # it is still named rather than assumed: a registration that says nothing would have
      # to change shape the day a second event exists.
      constants: { NONE: 0, EVEN: 1, ODD: 2, RTSCTS: 4, RX_RECEIVE: 1 },
      constructor: {
        function: :bareruby_uart_init,
        parameter_types: %i[Int32],
        # The frame, in the order the standard guideline states it. A binding that cannot
        # produce the frame asked for refuses; it never quietly sends a different one,
        # because a wrong frame is rubbish on the wire and there is nowhere safe to fall.
        keywords: { baud: 115_200, data_bits: 8, stop_bits: 1, parity: 0 }
      },
      methods: {
        # puts and write on a UART take the same printf expansion as the global puts.
        write: {
          function: :bareruby_uart_write, printf_function: :bareruby_uart_printf,
          parameter_types: %i[String], return_type: :Int32
        },
        puts: {
          function: :bareruby_uart_puts, printf_function: :bareruby_uart_printf,
          parameter_types: %i[String], return_type: :Nil
        },
        # **The whole of what the hardware answers for receiving**: take the next byte off
        # the queue, look at it without taking it, and say how deep the queue is. Filling
        # it from the line is the fourth, and it is the interrupt's rather than a name a
        # program says. Everything above them — a line, a count of bytes, whether a read
        # would find anything — is the class's own Ruby, because none of it is about
        # hardware. Touching any of these arms the receive interrupt, which is what buys
        # the 256-byte queue; bytes_available answers its depth once that unit is linked,
        # and the hardware flag (0 or 1) before.
        read_byte: { function: :bareruby_uart_read_byte, parameter_types: [], return_type: :Int32 },
        peek: { function: :bareruby_uart_peek, parameter_types: [], return_type: :Int32 },
        bytes_available: {
          function: :bareruby_uart_bytes_available, parameter_types: [], return_type: :Int32
        },
        flush: { function: :bareruby_uart_flush, parameter_types: [], return_type: :Nil },
        clear_rx_buffer: {
          function: :bareruby_uart_clear_rx_buffer, parameter_types: [], return_type: :Nil
        },
        # What the send side still owes the wire, and the break the standard guideline
        # defines. bytes_to_write is the counterpart of bytes_available.
        bytes_to_write: {
          function: :bareruby_uart_bytes_to_write, parameter_types: [], return_type: :Int32
        },
        send_break: {
          function: :bareruby_uart_send_break, parameter_types: %i[Int32], return_type: :Nil
        },
        clear_tx_buffer: {
          function: :bareruby_uart_clear_tx_buffer, parameter_types: [], return_type: :Nil
        },
        # **The receive notification says which port and which event, and stops there.**
        # Registering is what arms the interrupt and so what buys the queue; the block runs
        # later, in thread mode while a wait waits. It is handed the peripheral it was
        # registered on — so that it need not have been kept in a name the handler cannot
        # see — and the event that fired. What arrived, and whether it amounts to a line,
        # it reads for itself.
        irq: {
          function: :bareruby_uart_irq, parameter_types: %i[Int32], return_type: :Nil,
          block: :realtime_handler, block_parameter_types: %i[self Int32]
        }
      },
    # Where the expansion's variable arguments begin. It is a fact about this function's
    # signature, so it is stated here rather than in a table the compiler keeps.
    variadic: { bareruby_uart_printf: 2 },
    # **How deep the receive queue is, is settled while compiling.** Its storage is static,
    # so the number has to be known where the storage is declared and cannot be handed to
    # the constructor as the rest of the frame is. A program that says nothing gets what
    # the binding chooses; one that asks reaches a binding that owns its queue, and one
    # whose queue belongs to the core it is built on refuses rather than quietly giving a
    # different size.
    definitions: %i[rx_buffer_size],
    # What UART is above the hardware's vocabulary, written once rather than once per
    # board. can_read_line was four identical C functions until it moved here.
    library: File.expand_path("uart/program.rb", __dir__),
    required_name: "uart",
    declaration: <<~CPP.chomp,
      typedef struct {
          int32_t id;
          int32_t baud;
          int32_t data_bits;
          int32_t stop_bits;
          int32_t parity;
      } bareruby_uart_t;

      void bareruby_uart_init(
          bareruby_uart_t *self, int32_t id, int32_t baud,
          int32_t data_bits, int32_t stop_bits, int32_t parity);
      int32_t bareruby_uart_write(bareruby_uart_t *self, const char *value);
      void bareruby_uart_puts(bareruby_uart_t *self, const char *value);
      void bareruby_uart_printf(bareruby_uart_t *self, const char *format, ...);
      int32_t bareruby_uart_read_byte(bareruby_uart_t *self);
      int32_t bareruby_uart_peek(bareruby_uart_t *self);
      int32_t bareruby_uart_bytes_available(bareruby_uart_t *self);
      int32_t bareruby_uart_bytes_to_write(bareruby_uart_t *self);
      void bareruby_uart_send_break(bareruby_uart_t *self, int32_t milliseconds);
      void bareruby_uart_flush(bareruby_uart_t *self);
      void bareruby_uart_clear_rx_buffer(bareruby_uart_t *self);
      void bareruby_uart_clear_tx_buffer(bareruby_uart_t *self);

      typedef void (*bareruby_uart_irq_handler_t)(bareruby_uart_t *self, int32_t event);
      void bareruby_uart_irq(
          bareruby_uart_t *self, int32_t events, bareruby_uart_irq_handler_t handler);
    CPP
    units: {
      uart: %i[bareruby_uart_init bareruby_uart_write bareruby_uart_puts
               bareruby_uart_printf bareruby_uart_bytes_available
               bareruby_uart_flush bareruby_uart_clear_rx_buffer bareruby_uart_clear_tx_buffer
               bareruby_uart_bytes_to_write bareruby_uart_send_break],
      # **One queue, and everyone reads it.** Whatever touches the receive side brings it,
      # a registration included — the handler is a consumer of the same queue as `gets`,
      # taking bytes with the same call, and whichever asks first gets the byte.
      uart_receive: %i[bareruby_uart_read_byte bareruby_uart_peek bareruby_uart_irq],
      uart_interrupt: %i[bareruby_uart_irq]
    }
  )
end
