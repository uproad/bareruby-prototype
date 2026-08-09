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
      constants: { NONE: 0, EVEN: 1, ODD: 2, RTSCTS: 4 },
      constructor: {
        function: :bareruby_uart_init,
        parameter_types: %i[Int32],
        keywords: { baud: 115_200, parity: 0, stop_bits: 1 }
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
        read: { function: :bareruby_uart_read, parameter_types: %i[Int32], return_type: :arena_string },
        gets: { function: :bareruby_uart_gets, parameter_types: [], return_type: :arena_string },
        # The Arduino HardwareSerial shape: non-blocking byte access over the
        # interrupt-fed ring, -1 when nothing waits. Touching either arms the receive
        # interrupt, which is what buys the 256-byte ring; bytes_available answers the
        # ring's depth once that unit is linked, and the hardware flag (0 or 1) before.
        read_byte: { function: :bareruby_uart_read_byte, parameter_types: [], return_type: :Int32 },
        peek: { function: :bareruby_uart_peek, parameter_types: [], return_type: :Int32 },
        bytes_available: {
          function: :bareruby_uart_bytes_available, parameter_types: [], return_type: :Int32
        },
        can_read_line: {
          function: :bareruby_uart_can_read_line, parameter_types: [], return_type: :Bool
        },
        flush: { function: :bareruby_uart_flush, parameter_types: [], return_type: :Nil },
        clear_rx_buffer: {
          function: :bareruby_uart_clear_rx_buffer, parameter_types: [], return_type: :Nil
        },
        clear_tx_buffer: {
          function: :bareruby_uart_clear_tx_buffer, parameter_types: [], return_type: :Nil
        },
        # The receive interrupt. Enabling it is what buys the 256-byte ring the binding
        # keeps filled from its ISR; the block runs later, in thread mode while sleep_ms
        # waits, handed each completed line as a borrowed view of the binding's buffer.
        on_line: {
          function: :bareruby_uart_on_line, parameter_types: [], return_type: :Nil,
          block: :realtime_handler, block_parameter_types: %i[StringView]
        }
      },
    # Where the expansion's variable arguments begin. It is a fact about this function's
    # signature, so it is stated here rather than in a table the compiler keeps.
    variadic: { bareruby_uart_printf: 2 },
    required_name: "uart",
    declaration: <<~CPP.chomp,
      typedef struct {
          int32_t id;
          int32_t baud;
          int32_t parity;
          int32_t stop_bits;
      } bareruby_uart_t;

      void bareruby_uart_init(
          bareruby_uart_t *self, int32_t id, int32_t baud, int32_t parity, int32_t stop_bits);
      int32_t bareruby_uart_write(bareruby_uart_t *self, const char *value);
      void bareruby_uart_puts(bareruby_uart_t *self, const char *value);
      void bareruby_uart_printf(bareruby_uart_t *self, const char *format, ...);
      bareruby_string_t *bareruby_uart_read(
          bareruby_uart_t *self, bareruby_arena_t *arena, int32_t length);
      bareruby_string_t *bareruby_uart_gets(bareruby_uart_t *self, bareruby_arena_t *arena);
      int32_t bareruby_uart_read_byte(bareruby_uart_t *self);
      int32_t bareruby_uart_peek(bareruby_uart_t *self);
      int32_t bareruby_uart_bytes_available(bareruby_uart_t *self);
      bool bareruby_uart_can_read_line(bareruby_uart_t *self);
      void bareruby_uart_flush(bareruby_uart_t *self);
      void bareruby_uart_clear_rx_buffer(bareruby_uart_t *self);
      void bareruby_uart_clear_tx_buffer(bareruby_uart_t *self);

      typedef void (*bareruby_uart_line_handler_t)(bareruby_string_view_t *line);
      void bareruby_uart_on_line(bareruby_uart_t *self, bareruby_uart_line_handler_t handler);
    CPP
    units: {
      uart: %i[bareruby_uart_init bareruby_uart_write bareruby_uart_puts
               bareruby_uart_printf bareruby_uart_bytes_available bareruby_uart_can_read_line
               bareruby_uart_flush bareruby_uart_clear_rx_buffer bareruby_uart_clear_tx_buffer],
      uart_receive: %i[bareruby_uart_read bareruby_uart_gets],
      uart_interrupt: %i[bareruby_uart_on_line bareruby_uart_read_byte bareruby_uart_peek]
    }
  )
end
