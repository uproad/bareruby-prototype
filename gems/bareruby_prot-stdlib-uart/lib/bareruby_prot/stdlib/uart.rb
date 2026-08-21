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
        parameter_types: [],
        # **Everything the line is opened with is named**, in the order and with the
        # spelling PicoRuby and the standard guideline use — which unit, which pins, the
        # frame, and whether the line has flow control. A binding that cannot produce what
        # was asked for refuses; it never quietly opens a different line, because a wrong
        # frame is rubbish on the wire and a pin that was not taken is a line that is not
        # there. **-1 is how a pin says nothing was asked**, and the board's own is used.
        keywords: {
          unit: 0, txd_pin: -1, rxd_pin: -1, baudrate: 9600, data_bits: 8, stop_bits: 1,
          parity: 0, flow_control: 0, rts_pin: -1, cts_pin: -1
        }
      },
      methods: {
        # puts and write on a UART take the same printf expansion as the global puts.
        # What the line was opened at, read back. It is in the struct already, so the
        # header answers it and no binding writes anything.
        baudrate: { function: :bareruby_uart_baudrate, parameter_types: [], return_type: :Int32 },
        # **What the line was opened with can be changed afterwards.** Every part of it is
        # optional, and **-1 is how one says it is not being changed** — this language has
        # no keyword that can be left out, so not changing a thing has to be sayable.
        setmode: {
          function: :bareruby_uart_setmode, parameter_types: [], return_type: :Nil,
          keywords: {
            baudrate: -1, data_bits: -1, stop_bits: -1, parity: -1, flow_control: -1,
            rts_pin: -1, cts_pin: -1
          }
        },
        # What a line ends with, on both sides of it: what `puts` puts after what it was
        # given, and what `gets` reads up to. It is the class's own state — no hardware
        # knows what a line is — so the header holds it and no binding writes it.
        :line_ending= => {
          function: :bareruby_uart_line_ending_set, parameter_types: %i[String], return_type: :Nil
        },
        # The byte a line ends with. **`gets` is written in Ruby and a static string
        # answers nothing here** — no size, no index, no ord — so the ending it was given
        # is not something Ruby can look inside. This is how it asks.
        line_terminator: {
          function: :bareruby_uart_line_terminator, parameter_types: [], return_type: :Int32
        },
        write: {
          function: :bareruby_uart_write, printf_function: :bareruby_uart_printf,
          parameter_types: %i[String], return_type: :Int32
        },
        # **What ends a line is the line's, not the compiler's.** An interpolation is
        # expanded into a printf, and there are two of them here for that reason: the one
        # puts reaches puts the ending after what it formatted, and the one write reaches
        # puts nothing. Written with one, an interpolated write quietly became a puts.
        puts: {
          function: :bareruby_uart_puts, printf_function: :bareruby_uart_printf_line,
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
    variadic: { bareruby_uart_printf: 2, bareruby_uart_printf_line: 2 },
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
          int32_t unit;
          int32_t txd_pin;
          int32_t rxd_pin;
          int32_t baudrate;
          int32_t data_bits;
          int32_t stop_bits;
          int32_t parity;
          int32_t flow_control;
          int32_t rts_pin;
          int32_t cts_pin;
          const char *line_ending;
      } bareruby_uart_t;

      void bareruby_uart_init(
          bareruby_uart_t *self, int32_t unit, int32_t txd_pin, int32_t rxd_pin,
          int32_t baudrate, int32_t data_bits, int32_t stop_bits, int32_t parity,
          int32_t flow_control, int32_t rts_pin, int32_t cts_pin);

      /* Reading back what the line was opened at is reading a field the constructor
         already wrote, so it is answered here rather than four times over. */
      static inline int32_t bareruby_uart_baudrate(bareruby_uart_t *self) {
          return self->baudrate;
      }

      /* **What a line ends with is the class's, not the hardware's.** No board knows what
         a line is, so the ending lives in the struct and is set and read here; only the
         calls that put bytes on the wire ever look at it. */
      static inline void bareruby_uart_line_ending_set(
          bareruby_uart_t *self, const char *value) {
          self->line_ending = value;
      }

      static inline int32_t bareruby_uart_line_terminator(bareruby_uart_t *self) {
          const char *ending = self->line_ending;
          int32_t last = 0;
          while (*ending != '\0') {
              last = (int32_t)(unsigned char)*ending;
              ++ending;
          }
          return last;
      }

      /* **-1 is how setmode says a thing is not being changed**, so what a binding has to
         apply is the struct with the changes folded into it. Which fields moved is not a
         question any one board answers differently, so the folding happens once here and
         each binding applies what it finds. */
      static inline void bareruby_uart_settle(
          bareruby_uart_t *self, int32_t baudrate, int32_t data_bits, int32_t stop_bits,
          int32_t parity, int32_t flow_control, int32_t rts_pin, int32_t cts_pin) {
          if (baudrate >= 0) { self->baudrate = baudrate; }
          if (data_bits >= 0) { self->data_bits = data_bits; }
          if (stop_bits >= 0) { self->stop_bits = stop_bits; }
          if (parity >= 0) { self->parity = parity; }
          if (flow_control >= 0) { self->flow_control = flow_control; }
          if (rts_pin >= 0) { self->rts_pin = rts_pin; }
          if (cts_pin >= 0) { self->cts_pin = cts_pin; }
      }

      void bareruby_uart_setmode(
          bareruby_uart_t *self, int32_t baudrate, int32_t data_bits, int32_t stop_bits,
          int32_t parity, int32_t flow_control, int32_t rts_pin, int32_t cts_pin);
      int32_t bareruby_uart_write(bareruby_uart_t *self, const char *value);
      void bareruby_uart_puts(bareruby_uart_t *self, const char *value);
      void bareruby_uart_printf(bareruby_uart_t *self, const char *format, ...);
      void bareruby_uart_printf_line(bareruby_uart_t *self, const char *format, ...);
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
      uart: %i[bareruby_uart_init bareruby_uart_setmode bareruby_uart_write bareruby_uart_puts
               bareruby_uart_printf bareruby_uart_printf_line bareruby_uart_bytes_available
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
