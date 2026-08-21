# History

This prototype exists to answer one question by running it, and its value is the record of
what ran and what it cost. That record is here: what each milestone proved, what was
deliberately left out of it, and the sizes and timings measured while proving it. The
[README](README.md) says how to use the thing; this file says what it has shown.

Figures are `text` (flash), `bss` (RAM) and artifact size, measured on the target named
beside them. Unless a line says otherwise they were taken under the toolchain versions the
README lists.

## What has been covered

### The language, milestone by milestone

- **M0** — Prism → BRAST → TAST → LIR → C++ for the representative program the design
  documents use (`ref.rb`), compiled with the host `g++` and executed.
- **M1** — the same eight passes produce an rp2040 firmware image for the blink
  program (`samples/blink.rb`), built with pico-sdk into a real `.uf2` and flashed onto a
  Raspberry Pi Pico, where it blinks.
- **M2** — the MVP language and the three demos it is defined by: blink, servo
  (`samples/servo.rb`) and UART logging (`samples/logger.rb`). Adds pass 8 and, in the
  language, control flow, strings with printf-expanded interpolation, keyword arguments,
  symbols, `Fixed`, and the PWM, UART and Machine bindings.
- **M2.5** — inheritance and modules flattened at compile time with `super`, begin and
  rescue with `--no-exceptions`, the interpolation assignment form, and require
  expansion. No new pass; pass 5 does the flattening.
- **M2.6** — the ADC binding (`samples/adc.rb`). `read` and `read_voltage` return `Fixed`
  rather than the guideline's `Float`, `read_raw` returns `Int32`, and a pin with no
  converter channel is passed through as written: what values an interface accepts is the
  running code's business, not the compiler's, which checks types and nothing else. No new
  pass.
- **M2.7** — fixed-capacity arrays (`samples/array.rb`): `Array.new(n[, init])`, array
  literals, `[]`, `[]=`, `size` and `dup`. Single element type, capacity settled while
  compiling. Assignment shares the array as Ruby does, and only `dup` duplicates it;
  indexing is pointer arithmetic and is not range checked. No new pass.
- **M3 — the arena**, the third layer of the memory model (`samples/arena.rb`):
  `arena(N) { … }` is a **form rather than an object**. There is no `Arena.new`, no block
  parameter and no `reset`: an arena cannot be named, passed or stored, so a program can
  only ever be inside one. `arena(N)` asks for N bytes *here* — finding no region it takes
  the buffer its own site reserved and becomes the current one, finding a region it becomes
  a release point and checks on the way in that N bytes are left. Which role a block plays
  is settled when it is entered rather than while compiling, because a block written in a
  method is outermost or nested depending on who calls that method. Written without a size,
  `arena { … }` asks for nothing and is a release point only. Allocation bumps one pointer
  and each region is a static buffer belonging to the site that declared it: asking for 1024
  bytes more moves `bss` by exactly 1024. Leaving a block hands back everything it took, done
  by a guard whose destructor runs on the way out, so an exception leaving the block releases
  as well. **Which region an allocation comes from is one implicit pointer** — a method
  allocates and hands the result back without being told where from, which is why the arena
  needs no parameter and no lifetime analysis over an object graph. Running out throws rather
  than stopping, so a program can answer it; with `--no-exceptions` it falls back to stopping,
  the rule a bare `raise` already follows. An allocation may not be stored in an instance
  variable or in a local the block did not introduce. No new pass.
- **M3 — the growing array** (`samples/arena.rb`): `Arena::Array.new(n)` and
  `Arena::Array.new(n, init)`, whose length is a run-time value — the case the first two
  layers cannot serve — plus `[]`, `[]=`, `size`, `length`, `<<` and `dup`. The empty literal
  `[]` is sugar for it inside a region, and `::Array` is how a program reaches the
  fixed-capacity one from in there. **Writing past the end grows it**, which is why it cannot
  be a handle held by value: growing takes a bigger block from the region and moves both the
  pointer and the length, and a copy of a handle would keep naming the block the array has
  left behind — whether an append were seen would depend on how much room happened to be
  left. So, like the string, the handle lives in the region and a binding is its address.
  Elements a program has not written read as the default of their type, and a gap left by
  writing past the end reads the same as a fresh array does: every element type an array can
  hold has a default of all zero bits, so one clear serves them all. Indexing stays pointer
  arithmetic and is not range checked. No new pass.
- **M3 — the variable-length string** (`samples/string.rb`), the other value the first two
  layers cannot hold: `Arena::String.new`, `.new("text")`, `.new(other_string)` and
  `.new("count: #{n}")` create one — and the empty literal `""` is sugar for it inside a
  region — and it answers `<<`, `+`, `size`, `length`, `dup`,
  `==`, `!=` and `to_s`. It grows: appending past the block it holds takes a bigger one from
  the region and copies into it, and the block left behind stays until the region is
  released, because an arena has no free. Both its bytes and its handle come from the
  region, so a method can create one and hand it back, and every binding is the address of
  the one string — `b = a` then `b << " C"` is seen through `a`, exactly as in Ruby, while
  `+` and `dup` answer new strings. The interpolation form is the one that needs no
  estimate: `vsnprintf` says how long a rendering is before writing it, where an
  interpolation assigned to a fixed-capacity local (M2.5) has to bound every part while
  compiling. The runtime owns the representation — the generated code reads no field of a
  string. No new pass.
- **M3 — UART receive** (`samples/uart_receive.rb`): `uart.read(n)` takes exactly the
  requested bytes on the successful path and `uart.gets` takes a line including its
  newline, both as variable-length strings. The Ruby calls keep their standard shape;
  when they appear inside an `arena` block, pass 5 threads that innermost region into the
  binding as the place the result belongs. The hosted UART receives its byte stream on
  stdin, and the rp2040 binding reads from the selected hardware UART with pico-sdk. The
  target-specific receive code is a separate translation unit and is linked only when a
  program calls `read` or `gets`. The empty-buffer `nil` path waits for M3's nilable type;
  this prototype implements only the successful receive the feasibility question needs.
  No new pass.
- **M3 — I2C** (`samples/i2c.rb`): `I2C.new(id, frequency:)`, `write(address,
  *outputs)` and `read(address, length, *outputs)`. Integer, fixed-array, static-string and
  variable-length-string outputs are flattened in order into one temporary byte string,
  so one Ruby call remains one bus transaction. As with UART receive, pass 5 supplies the
  innermost active arena without adding a Ruby argument: it owns both that temporary and
  the variable-length string `read` returns. A read with outputs writes them without a
  stop, then starts the read with a repeated start. The hosted bus takes read bytes from
  stdin; the rp2040 binding uses pico-sdk, with I2C0 on GP4/GP5 and I2C1 on GP6/GP7. C++
  string literals now encode arbitrary bytes rather than requiring valid UTF-8. NAK and
  timeout handling stay outside the successful path this prototype implements. The
  target-specific sources are linked only when an I2C operation reaches the program. No
  new pass.
- **M3 — nilable values** (`samples/nilable.rb`, `samples/definite_assignment.rb`): `nil`
  joins with `T` as inferred `T?`
  and lowers uniformly to a struct containing an explicit presence tag and the ordinary
  value representation. A local tested by `if` or assigned in a `while` condition is
  narrowed to `T` in its true path, `nil?` reads absence, local safe navigation produces
  another nilable value, and `maybe || default` unwraps or substitutes without exposing
  the tag to Ruby. A missing `else` contributes `Nil`; a local first assigned on a path
  that may not run is declared beforehand in the Nil state; and an instance variable not
  assigned on every path through `initialize` starts in that same state — where a method
  `initialize` calls counts as one of those paths, so a field a constructor sets through a
  helper is an ordinary `T` rather than a `T?`. The sample
  exercises both `Int32?` and a variable-length
  string pointer in the same representation scheme. This feasibility slice follows the
  local-only withdrawal line: instance-variable narrowing and invalidation are not
  implemented. No new pass.
- **M4 — experimental GPIO interrupts** (`samples/interrupt.rb`):
  `button.on_interrupt(edge: GPIO::EDGE_FALL) { ... }` lowers its non-capturing,
  zero-argument block to a realtime handler and registers it with the GPIO receiver.
  The hosted binding records registration and calls the handler synchronously once, so
  the sample demonstrates GP15 falling-edge input driving a GP25 LED write without
  hardware. The rp2040 binding keeps one zero-argument handler pointer and invokes it
  from pico-sdk's GPIO callback bridge. Pass 11 rejects arena storage or allocation in a
  realtime handler and in user methods reachable from it. This is deliberately
  provisional: it supports one handler, `EDGE_FALL` only, no captures, no unregister,
  no generalized interrupt API, and no production diagnostics. Built with pico-sdk
  2.3.0, the sample produced a 27,648 B UF2 with 17,672 B of ELF text and 1,508 B of bss;
  it was built but not hardware-flashed.
- **M5 — UART receive interrupts** (`samples/uart_on_line.rb`):
  `uart.on_line { |line| ... }` generalizes the M4 machinery — a realtime handler's
  parameters are now the declaration's to state, as `block_parameter_types:` beside the
  block kind, and the registration arguments between the receiver and the handler come
  from the declared keywords rather than a fixed `edge` slot, so GPIO's shape is one case
  of the form rather than the form. The handler is handed each completed line as a
  `StringView` — a new non-owning type, a pointer and a length into the binding's buffer,
  declared in the binding header together with its one operation
  (`bareruby_text_view_equal`, deliberately named outside the `bareruby_string_` family
  so a view never links the string runtime or the arena) — and answers `==`/`!=` against
  a static string, nothing else. Enabling the interrupt is what buys the memory: the new
  `uart_interrupt` unit holds a static 256-byte ring the ISR pushes received bytes into
  and a 256-byte line-assembly buffer the view points at, linked only when a program says
  `on_line`. All policy — LF/CRLF framing, the trailing newline stripped, the 255-byte
  cap with overlong lines discarded to the next newline, the handler call itself — runs
  in thread mode: `bareruby_sleep_ms`/`bareruby_sleep` became drain loops calling a hook
  the always-linked unit declares `__attribute__((weak))` as a no-op and the interrupt
  unit overrides, the STM32 startup-file move made at the unit boundary. Per platform:
  STM32Cube installs strong `USARTx_IRQHandler`s reading SR then DR (guarded by which
  instances the device header defines — an F401 has no USART3/UART4/UART5), pico-sdk uses
  `irq_set_exclusive_handler` plus `uart_set_irq_enables`, the Arduino binding
  deliberately takes no vector — HardwareSerial's own interrupt-filled buffer stands in
  for the ring and the drain empties it — and the hosted binding plays the ISR itself
  from non-blocking stdin, so `printf 'ON\r\nOFF\n' |` exercises the whole path without
  hardware. Still provisional, as M4 was: one registration per program, the `asleep`
  family does not drain, a full ring drops bytes silently, and a view stored past its
  block dangles by design. On the NUCLEO-F446RE the sample builds to 20,064 B of ELF
  text and 2,272 B of bss; verified on host, built for every board of all four bindings.
- **M6 — Arduino HardwareSerial-shaped receive** (`samples/uart_buffered.rb`): the
  definition was pinned first — everything Arduino's HardwareSerial can receive — which
  shrank the problem to exactly four pieces, because that framework does no framing at
  all: an ISR-fed ring, non-blocking reads over it, a clock for the timeout family, and
  the stop bit `begin()`'s config byte carries. So: `UART.new` takes `stop_bits:` (1 or
  2, applied per platform as `UART_STOPBITS_2` / `uart_set_format` — which also made the
  Pico binding stop ignoring parity — / `SERIAL_8N2`-family constants); `read_byte` and
  `peek` answer the next byte or -1 without blocking or an arena; `bytes_available`
  answers the ring's depth — its polling definition in the always-linked uart unit turned
  weak, and the uart_interrupt unit carries the strong override, so a program that never
  buffers keeps the hardware flag and pays nothing; and bare `ticks_ms` reads
  milliseconds since boot into an Int32 (HAL_GetTick / to_ms_since_boot / millis /
  CLOCK_MONOTONIC), so Arduino's `setTimeout`/`readBytesUntil`/`parseInt` family needs no
  declarations of its own — the sample composes readBytesUntil from the primitives in
  eight lines of Ruby. The receive side arms on first touch — a registration or a
  buffered read — which is now the one moment the 256-byte ring is bought; the ring keeps
  one consumer, a registered on_line handler taking precedence over the read family, and
  the ISRs discard parity-failed bytes as Arduino's core does. Known divergences,
  recorded: one receive port per program where Arduino serves four, and `read`/`gets`
  stay on their blocking hardware path rather than the ring. Verified on host including
  the timeout path; built for every board of all four bindings.
  *The "5–7 data bits are not offered (the F4's UART cannot)" recorded here was wrong on
  both halves; see the entry below.*
- **The frame the guideline states** (`samples/uart_format.rb`): the UART class was read
  against the standard it claims to follow, and against PicoRuby, and **the class was the
  one that had been dropping things**. `stop_bits:`, arrived at above by way of Arduino's
  `begin()` config byte, turns out to be a name and a default the guideline and PicoRuby
  both already carry; nothing was invented. Missing outright were `data_bits:`,
  `bytes_to_write` and `send_break`, all three of which the guideline states.
  **The claim that the F4 cannot offer 7 data bits was wrong**: an F4's word length counts
  the parity bit, so `UART_WORDLENGTH_8B` with parity on *is* 7E1 — the binding simply
  never used that combination. What an F4 truly cannot spell is 5, 6, and 7 without
  parity. And it was the wrong place to decide from: pico-sdk takes 5..8 in a field of its
  own and Arduino's core spells all four, so **letting the narrowest binding fix the API
  throws away what the other two hold natively**. So the frame is asked for, and a device
  that cannot produce it **refuses** (`bareruby_board_fault`) rather than sending a
  different one — a wrong frame is rubbish on the wire and there is nowhere safe to fall,
  which is what separates this from the LED that no-ops on a board without one.
  Per platform: pico-sdk passes the three fields straight to `uart_set_format`; the
  Arduino config byte is built from its bit fields (data bits in 2..1, stop in 3, parity
  in 5..4) instead of a table of thirty-six names; the F4 sums data and parity and admits
  only 8 or 9. `send_break` cost the most per platform — the PL011 holds BRK for exactly
  as long as asked, an F4 has only `SBK` (one break character) so the span is served by
  repeating it, and **Arduino's core has no break at all**, so the pin is taken back from
  the transmitter and held low, which is the one place the frame kept in the struct is
  read back. On pico1h the sample builds to 40,864 B of text and 3,608 B of bss (73,728 B
  UF2), on the Mega a 16,148 B hex. Verified on host; built for pico1h, pico2w and
  mega2560. **The refusal path is not exercised** — no STM32 target on this desk — and
  no board was flashed.
- **A keyword the declaration does not have is refused** — which keywords a peripheral
  takes is stated in its declaration, and pass 5 turned each declared one into a trailing
  positional argument and let every other one fall on the floor. `UART.new(0, data_bits: 7,
  parity: UART::EVEN)` therefore read as a 7E1 program while the wire carried 8N1, and
  `flow_control:` — whose constant `UART::RTSCTS` the class publishes — was accepted and
  did nothing. The pass now compares what the program wrote against what the declaration
  holds and stops at the difference: `UART.new takes baud:, data_bits:, stop_bits:,
  parity:, not flow_control:`. All three places a peripheral is handed keywords are
  covered — the constructor, a registration that takes a block, and a plain method, which
  declares none and now says so rather than failing several steps later with a nil. This is
  a diagnostic, which this prototype does not otherwise write; it belongs here because a
  keyword that is dropped in silence makes the claims of every other entry above
  unverifiable by running them, which is the only way anything here is verified. No sample
  demonstrates it: a program that must be refused cannot sit among the ones that must
  compile.
- **A peripheral class carries Ruby of its own** (`samples/peripheral_ruby.rb`): a
  peripheral was a mapping onto C functions and nothing else, so anything above them had
  nowhere to live but C — and a sentence that is not about hardware got written once per
  board. `can_read_line` was four C functions in four bindings, three of which asked the
  same question and the fourth of which answered `false` and nothing else. It is now nine
  lines of Ruby in the gem that declares UART, spliced into the program being compiled
  where a require would have put it, and it lowers to `static bool
  UART_can_read_line(bareruby_uart_t *self)` beside the program's own functions — the
  binding's struct, not one named after the class, because the C functions all take that
  one. A call inside it with no receiver reaches the mapping (`bytes_available`) or the
  class (`can_read_line` from the method the sample adds), asked in that order.
  **A class opened twice is now one class**, as it is in Ruby: the bodies join in written
  order and a later definition replaces an earlier one, which is what lets the gem bring
  a body and the program still add to it. It cost nothing to install: `samples/blink.rb`,
  which names no UART, is 43,940 B of text and 6,672 B of bss on pico1h both before and
  after, to the byte — the class arrives in every program and pays only where something
  calls it, once the empty `initialize` every class is given stopped being emitted for a
  peripheral (the binding's constructor is the real one). Where it is called it cost 112 B:
  a program looping on `can_read_line` over `read_byte` is 45,208 B of text against 45,096
  B with the C version, because one call became two — and on that board it also changed
  which queue the answer is about, from the hardware flag to the ring `read_byte` reads,
  which is the coherent one. The sample is 45,448 B of text and 7,208 B of bss on pico1h
  (81.0 KB UF2) and 14,556 B of text and 2,512 B of bss on the F4. An instance variable in
  such a body is not implemented — the storage belongs to the binding's struct — and a
  name the mapping already has still wins over one written in Ruby. Verified on host with
  bytes piped in; built for pico1h, mega2560 and f446, and no board was flashed.
- **One receive queue, and everyone reads it** (`samples/uart_one_queue.rb`): the receive
  side had two — an interrupt-fed ring, and the hardware that `read` and `gets` polled
  directly — and which one a byte landed in decided who could see it. On the host, asking
  `peek` once moved everything waiting into the ring and left `gets` reading an empty
  stdin, where it appended EOF until the region ran out and the program aborted; asked the
  other way round, `gets` took its line and the rest of the input was simply gone, with no
  exception. On a board the same collision wore a different face: the ISR reads the data
  register, which clears the flag a polling `gets` is waiting for, so `gets` waits for
  ever. **There is now one queue**, and `gets`, `read`, a registered handler and
  `bytes_available` all reach it through `read_byte` — the handler included, which is what
  makes first-come-first-served true rather than a hope: the line assembler takes bytes
  with the same call a program would, and what it did not take is nobody's loss but the
  one who did not ask. What the hardware answers for shrank to taking the next byte,
  looking at it, and saying how deep the queue is, with the interrupt filling it; **a line
  is not something a wire has**, so where one ends is decided in UART's own Ruby, once,
  rather than in every binding. `gets` and `read` moved there with it, which needed `<<`
  to take a character code as Ruby's does — the runtime had the call and nothing written
  in Ruby could reach it. `clear_rx_buffer` empties the queue again, which it had stopped
  doing when the ring arrived. On the Arduino side there is still exactly one queue and it
  is the core's own, so that binding buys no second ring and overrides no clearing. What
  it cost, on pico1h: `samples/uart_receive.rb`, which only calls `gets` and `read`, went
  from 97,364 B of text and 7,044 B of bss to 97,756 B and 7,308 B — the 256-byte queue it
  never used to buy, plus the difference between a C loop over the hardware and a Ruby one
  over the queue. `samples/uart_on_line.rb` went from 44,876 B to 45,028 B of text with
  bss unmoved. The new sample is 97,892 B of text and 7,308 B of bss there (183.5 KB UF2),
  and 20,836 B of text and 2,532 B of bss on the F4. Not done here: the queue is still 256
  bytes with no way to ask for another size, `can_read_line` still answers whether *any*
  byte waits rather than a whole line, and a program waiting on a wire that has gone quiet
  now waits rather than aborting — on the host a closed stdin is such a wire. Verified on
  host with bytes piped in; built for pico1h, mega2560 and f446, and no board was flashed.
- **How deep the receive queue is, is the program's to say** (`samples/uart_rx_buffer.rb`):
  the queue was 256 bytes because that is what was written in four bindings, and there was
  no road for a number to travel from a program to the place a static buffer is declared.
  Keywords become trailing arguments of the call, and an argument arrives too late to give
  a buffer its dimension. So `rx_buffer_size:` **leaves the call**: it is declared as a
  keyword the build is settled by, pass 5 takes it out of the arguments, insists it is
  known while compiling, and it reaches the second stage as `#define
  BARERUBY_UART_RX_BUFFER_SIZE` in the shared header. The value travels beside the tree
  rather than in it — no later pass computes with it, so carrying it through four
  representations would be carrying it for nothing. It lands where it was asked to: on
  pico1h the sample moves `bss` from 6,940 B to 7,708 B, **exactly the 768 bytes between
  256 and 1024**, and text by 8 B, because the queue's indices now count entries instead
  of relying on a byte wrapping at 256. On the F4 the sample is 14,456 B of text and
  3,008 B of bss. **Only what a program actually asked for is written into the header**,
  which is what lets a binding tell a chosen size from an unmentioned one: the three that
  own a queue supply 256 when nothing was said, and the Arduino core, whose queue is its
  own and whose size is `SERIAL_RX_BUFFER_SIZE`, **stops the build** rather than running
  quietly at another size — the same answer that binding already gives a frame it cannot
  produce. Measured on the host: with the default, 300 bytes offered and 255 taken (the
  ring keeps one slot free); asking for 1024, 300 offered and 300 taken, 1000 offered and
  1000 taken. Verified on host; built for pico1h and f446, and `samples/uart_rx_buffer.rb`
  has no mega2560 build by design. No board was flashed.
- **The receive notification says which port and which event** (`samples/uart_rx_receive.rb`):
  `on_line` handed a handler a finished line, which meant the binding had to know what a
  line is — and four of them knew it in four identical copies, LF/CRLF framing, the
  255-byte cap and the discarding of an overlong line included. It is now
  `irq(UART::RX_RECEIVE) { |port, event| … }`: the handler is told the peripheral it was
  registered on and the event that fired, and **reads the queue itself** with the same
  call a program would. The port is a parameter because a handler starts with its
  parameters and nothing else — it cannot see the name the program kept. The event is a
  parameter although there is only one of them, because a registration that says nothing
  would have to change shape the day there is a second; one event exists, so what was
  registered for and what fired are still the same value, and the binding is where the two
  will have to be told apart. **`on_line` and the borrowed-string view went with it** —
  the view existed to hand a handler bytes a binding owned, and nothing hands one now, so
  its type, its comparison and the typedef in the header are gone. What that is worth on
  pico1h: 6,952 B of bss against 7,212 B for the `on_line` sample it replaces, **260 bytes
  of line buffer that no longer exists**; text is 45,276 B against 45,076 B, though the two
  are different programs — the old one compared a view against strings in C, the new one
  compares bytes in Ruby. On the F4 the sample is 13,512 B of text and 2,256 B of bss, and
  it is 11.6 KB of hex on the Mega. What was lost with it, and is worth saying: **a handler
  cannot assemble a line that arrives in two pieces**, because it keeps nothing between
  calls. Lines are still reached the other way — `gets` from the program's own loop, which
  is where the queue's Ruby lives. Verified on host with bytes piped in; built for pico1h,
  mega2560 and f446, and no board was flashed.
- **The line is spelled the way the standard says it is** (`samples/uart_flow_control.rb`):
  the class claims to follow the mruby/c Common I/O API guidelines and PicoRuby, and it was
  reading its own spelling in six places — `baud:` for `baudrate:`, a unit counted from the
  front of the call instead of named, a default of 115200 where both say 9600, no pins at
  all, and a `UART::RTSCTS` constant with nowhere to hand it. **Everything the line is
  opened with is now named**, in the order the documented constructor lists it: `unit:`,
  `txd_pin:`, `rxd_pin:`, `baudrate:`, `data_bits:`, `stop_bits:`, `parity:`,
  `flow_control:`, `rts_pin:`, `cts_pin:` — and `baudrate` reads back what it was opened
  at, answered by an inline in the header over a field the constructor already wrote,
  rather than by four bindings each writing the same line. **-1 is how a pin says nothing
  was asked for**, and the board's own is used. Which boards can give what differs, and
  each says so rather than opening a different line: an RP2040 puts a UART on any GPIO, so
  a pin asked for is taken and flow control is the PL011's own; the Arduino core reaches a
  USART's fixed pins and has no RTS/CTS at all; a CubeMX project has already bonded its
  port out. The last two **refuse** — the same answer they already give a frame they
  cannot produce. The naming reaches the C side too: the struct's fields are `unit` and
  `baudrate` now, and the hosted trace says `unit=` — one word per thing, through every
  layer. What it cost on pico1h: `samples/logger.rb` went from 44,740 B to 44,796 B of
  text with `bss` unmoved, which is the ten arguments and the pin choosing. The sample is
  44,788 B of text and 6,676 B of bss there, and 14,084 B of text and 1,980 B of bss on
  the F4. **Two of the eight deviations are not here**: `setmode` and `line_ending=` are
  their own change. And one is a deliberate divergence: PicoRuby names a unit with a
  symbol (`unit: :RP2040_UART0`), and this takes the number, because naming one needs a
  table of names per board that nothing else here would use yet. Verified on host; built
  for pico1h, mega2560 and f446, and no board was flashed — **the refusals on those two
  boards are compiled but not run**.
- **The mode and the line ending are the program's** (`samples/uart_line_ending.rb`): the
  last two deviations from the standard the class follows. `setmode` changes what the line
  was opened with and **says nothing about the parts it does not name** — every keyword is
  optional in the documented signature, and this language has no keyword that can be left
  out, so **-1 is how a thing says it is not being changed**, the same spelling a pin
  already used for "nothing was asked". Folding those into the struct is not a question any
  board answers differently, so the header does it once and each binding applies what it
  finds; the constructor and `setmode` end in the same per-binding `apply`, which is what
  makes them agree by construction. `line_ending=` reaches **both** sides of a line: what
  `puts` puts after the text, and what `gets` reads up to. It lives in the struct because
  no hardware knows what a line is, and `gets` — which is Ruby now — asks for the byte it
  ends with, because **a static string in this language answers nothing**: no size, no
  index, no `ord`, so the ending it was handed is not something Ruby can look inside. That
  reader is an addition this prototype needed rather than something the standard names.
  **A defect fell out of it**: an interpolation is expanded into a printf, and both `write`
  and `puts` reached the same one, which the compiler had already ended with a newline — so
  `uart.write("value=#{n}")` quietly sent a line where `uart.write("plain")` sent none. The
  ending is the peripheral's now, so there are two printfs, the compiler ends no line it is
  not the one writing, and an interpolated `write` sends exactly what it was given. On
  pico1h `samples/logger.rb` went from 44,796 B to 44,892 B of text with `bss` unmoved; the
  sample is 98,112 B of text and 7,308 B of bss there, and 22,028 B of text and 2,532 B of
  bss on the F4. Verified on host, where the trace now carries the ending beside the text;
  built for pico1h, mega2560 and f446, and no board was flashed.
### Bindings, boards and targets

- **The STM32Cube binding** — a user-owned NUCLEO-F446RE CubeMX project, kept under
  `.tools/stm32cube/`, owns clock, pin, startup, HAL initialization and the linker
  script. Pass
  12 adds HAL-backed GPIO, timing, LD2, USART2 and I2C1 translation units, entered from a
  CubeMX-preserved user section after every peripheral is initialized. `bareruby build`
  generates one application, synchronizes only the reached units, and links them against
  the HAL with `arm-none-eabi-g++`. A physical board has been programmed over SWD, with
  LD2 and USART2 exercised; that run predates the move off STM32CubeIDE's headless
  builder. I2C links against STM32CubeF4 HAL 1.28.3 but remains hardware-unverified.
  `samples/heartbeat.rb` links to 5416 B of text and 1644 B of bss on this board; the
  bss is the HAL's, since the whole of `Drivers/` is compiled and the linker drops what
  no call reaches.

  **Two of its units still fail to link together.** `bareruby_startup` had been left in
  the GPIO unit when GPIO moved out of the unit every build reaches, so a program that
  never touches a pin — `samples/heartbeat.rb` is one — linked against a definition it
  had no reason to have pulled in. Splitting one file into several makes *which* file a
  definition landed in a fact worth checking, and nothing checks it: every binding names
  its own units and the linker is the only thing that reads the answer.

- **The Arduino core binding** (`arduino-mega2560`) — an ATmega2560 at 16 MHz with 256 KB
  of flash and 8 KB of SRAM, reached through the Arduino core and built by `arduino-cli`.
  The core owns `main` and calls `setup` and `loop`, so this side supplies those two and
  the program's own loop never comes back out of the first of them.

  **What that build takes is not a build file but a directory.** A sketch is compiled
  whole and nothing outside it is compiled at all, so the declaration the first stage
  makes everywhere — these are the translation units this program reached for — is met by
  gathering exactly those into one directory and handing it over. The link boundary
  survives a build system this side does not own: a program that never touches I2C leaves
  `Wire.h` unmentioned, so the library is never even discovered, let alone linked. What
  comes out is a complete sketch, which opens in the Arduino IDE without this repository.

  `samples/heartbeat.rb` is 4190 B of flash and 657 B of SRAM, and blinks the board's LED
  on real hardware. `samples/features.rb`, `samples/fixed.rb` and `samples/string.rb`
  print on the board exactly what they print on the host, which puts the arena and the
  variable-length string runtime — 2963 B of the 8192 there are — on an eight-bit machine
  with nothing changed for it.

  **It is the first machine here whose natural word is not 32 bits, and it found three
  faults every 32-bit target had been agreeing with.** All three are fixed in code shared
  by every target, because all three were wrong everywhere and only visible here.

  - **A printf conversion names a width, not a language type.** `int32_t` is an `int` on
    a 64-bit machine and a `long` on this one, and a value crossing an ellipsis is not
    converted to a parameter's type, because there is no parameter. So an interpolation
    renders as `%ld` and pass 12 widens the value to `long`, which is 32 bits on both.
    Under `%d`, `"count=#{70000} step=#{7}"` printed `count=4464 step=1` on the board —
    the low half of the first value, and then its high half read as the second.
  - **`1 << 15` is a shift into the sign bit** where an `int` is 16 bits. The half added
    before `Fixed`'s rounding shift was being subtracted, and `(0.5 * 100).to_i32`
    answered 49.
  - **A `*` field width is not read** by the smallest `printf` a machine ships with, so a
    width handed over as a value never arrives at all. `Fixed#to_s` now carries one
    format per fraction width instead.

  The three cost 56 B of flash on a `raspberry-pi-pico` build of `samples/fixed.rb`
  (36644 B against 36700 B) and no RAM, which is the six format strings.

  What this core cannot be asked for is recorded in its
  [README](gems/bareruby_prot-binding-arduino/README.md): PWM has a duty and no frequency, because
  `analogWrite` picks one and offers no way to name another; the chip has pull-ups and no
  pull-downs; `%lld` is not implemented by this libc; and `begin` has no build here at
  all, because the core compiles with `-fno-exceptions` and this libc carries no
  unwinder. On a Pico the exception mechanism is a decision with a price; here it is
  simply absent.

- **The on-board LED** (`samples/heartbeat.rb`) — `OnboardLED.new`, then `on`, `off` and
  `write`. It is deliberately **not** a `GPIO` with a known pin number, because on a
  board that has an LED it is frequently not a GPIO at all: a Pico W drives its through
  the wireless chip, and GP25, where the plain Pico's LED sits, is that chip's select
  line instead. Sharing GPIO's interface would only have hidden that.

  **Which implementation a board takes is written down, not worked out.** How a board's
  indicator is reached is not a fact about the board alone: the same LED is `gpio_put` and
  `PICO_DEFAULT_LED_PIN` through pico-sdk, and `HAL_GPIO_WritePin` and `LD2_Pin` through a
  CubeMX project. Nor is it a fact about the binding alone, because a Pico and a Pico W differ
  under the very same SDK — one has its LED on a pin and the other behind a radio. It is a
  fact about the two together, so it lives where the two meet:

  ```ruby
  # gems/bareruby_prot-binding-pico_sdk/lib/bareruby_prot/binding/pico_sdk/machine/pico_w.rb
  module PicoSdkBinding
    module PicoW
      def self.onboard_led_file = ONBOARD_LED_RADIO_FILE

      def self.onboard_led_text = ONBOARD_LED_RADIO

      def self.onboard_led_libraries = [RADIO_LIBRARY]
    end

    MACHINES[:pico_w] = PicoW
  end
  ```

  A machine answers for itself, by naming what the binding beside it already carries. Nothing is
  worked out: `binding.rb` holds the C++ and the names, exactly as it does for GPIO and
  UART, and there is no branch in it that decides which board gets which. A machine a binding
  cannot reach has no file rather than a wrong answer, and a board that needs the radio's
  driver and its firmware blob linked says so itself rather than a build guessing from
  what it got. So the same six lines of Ruby reach every supported on-board LED. A board with no
  on-board LED is meant to accept all three calls and do nothing, so that the presence of
  an indicator never decides whether a program compiles; every board target here has one,
  so nothing exercises that.

  Reaching the wireless LED means bringing the radio up and uploading its firmware, and
  that costs **255 KB of flash**: `samples/heartbeat.rb` is 15336 B of text on a Pico and
  270236 B on a Pico W. A program that never lights the LED links none of it, so the
  charge falls on the feature rather than on the board.

  Verified on hardware both ways round. The one program blinks a Pico, whose LED is GP25,
  and a Pico 2 W, whose LED is on the radio — and on that same Pico 2 W,
  `samples/blink.rb` writing GP25 leaves the LED dark. Nothing in the Ruby differs
  between blinking and not except which class the LED is asked for. The Pico 2 and the
  Pico W are built but not run: neither board is here. They are the non-wireless and
  wireless halves of the pair already confirmed, so what is left unverified is the
  combination rather than either mechanism.

- **Targets** — one run compiles for as many machines as it is asked to. `host`, the two
  Pico boards, the two Pico W boards, the NUCLEO board and the Mega 2560 are named on the
  command line or in `target.yml`, and each gets its own directory under `build/`. The
  Pico targets share one pico-sdk binding and differ only in the board handed to the SDK,
  which is what makes a second chip a table entry rather than a second back end: one
  first stage over `samples/blink.rb` produced both an RP2040 and an RP2350 `.uf2`,
  Cortex-M0+ and Cortex-M33, from the same generated `main.cpp`. Both were flashed onto
  real boards and run. One `bareruby build` of `samples/heartbeat.rb` against the three
  entries on this desk takes 24 seconds and leaves an RP2040 `.uf2`, an RP2350 `.uf2` and
  an ATmega2560 `.hex` — three chips, and the third shares no instruction set with the
  other two. The Pico 2 board is a **Pico 2 W**, and it is where the naming rule stopped being
  an argument and became an observation: `samples/blink.rb` writes GP25, the build and
  the flash both succeed without a single warning, the program runs — and the LED stays
  dark, because on that board the LED is on the wireless chip and not on GP25. The same
  program on the Pico blinks. One chip, two boards, two outcomes, and nothing before the
  hardware could tell them apart.

- **What a peripheral call costs, and who removes it** (`samples/gpio_pico_loop.rb`) —
  every GPIO a Pico 1 brings out to its header, pulsed one after another with nothing
  between the writes, so the period of GP0 is one sweep and an oscilloscope reads the
  cost straight off a pin.

  A peripheral is a translation unit of its own, so `gp.write(1)` is a call across one
  where the hardware asks for a single store. Measured on a real Pico, GP0 came out at
  **137.07 kHz** — 7.295 µs a sweep, 912 cycles at 125 MHz, **140 ns and 17.5 cycles for
  one write**, against the two-cycle store the chip is capable of.

  **Nothing on this side can remove that call, and nothing on this side should.** The
  caller and the callee are never in front of the compiler at the same time, so the one
  party that has both is the linker — and it already knows how. `-flto` on the generated
  units and on the link is the whole change; there is no inliner here, no `inline` hint
  and no per-function rule. **This is what emitting C++ rather than instructions was
  for**: the optimizer is somebody else's and already written.

  The same board then reads **1.29–1.47 MHz** — about **ten times**. The two figures the
  scope alternates between are one measurement, not noise: 1468.571 × 7 and 1285.000 × 8
  are both 10.28 MHz, so it is quantizing a period of 681–778 ns at ±1 count. The loop
  is 73 instructions where it was 209 plus 52 calls into a nine-instruction callee, and
  the mask `1 << pin` has left the loop entirely — computed once per pin at the top and
  held, so the body is two stores to the SIO and nothing else. Per write: **~14 ns, about
  1.75 cycles**.

  **The second chip answers the same question differently, and that is the more
  interesting result.** A Pico 2 W runs the same program with the same 26 pins: 469
  instructions a sweep become 68, and it goes from **263.6–270.0 kHz to 1.29–1.47 MHz —
  about five times**, not ten. The RP2350's write is one `mcrr` to the GPIO coprocessor
  rather than two stores to the SIO, and its out-of-line callee is six instructions where
  the RP2040's is nine, so there was less call to remove in the first place.

  What is left once it is removed is what differs. Per instruction the RP2040 costs the
  same before and after — 1.35 cycles against 1.16–1.33 — while the **RP2350 goes from
  1.20 to 1.60**. Its LTO'd loop is 52 `mcrr` out of 68 instructions where the baseline
  was 52 out of 469: at 11% of the path the coprocessor write was hidden among ordinary
  instructions, and at 76% it is the path. It costs about **2 cycles against the RP2040's
  1.75**, so a 20% higher clock buys nothing here and **both chips land on the same
  681–778 ns sweep**. That attribution is inferred from the two measurements rather than
  measured on its own.

  Which is the shape of the answer worth keeping: removing the calls moves the floor to
  wherever the hardware's own cost is, and where that floor sits is a fact about the chip
  that only appears once everything above it is gone.

  **Only the units this build generated are given to it.** Asking it of the whole target
  drags in the SDK's sources, and pico-sdk reaches its own stdio through `-Wl,--wrap`: a
  wrapper nothing calls in the IR is dropped before the linker makes the reference that
  would have kept it, and holding all 160 wrapped symbols down would link every one of
  them into every program. That version built 31040 B against 27052 B. Confined to the
  generated units it is **26552 B — smaller than not doing it at all**, because the calls
  go and the callees go with them, and it is instruction-for-instruction as fast. The
  boundary worth crossing was the one between generated units anyway; past it the build
  belongs to somebody else.

  It costs nothing anywhere else: `blink` 30580 → 30372 B of text, `fixed` 41256 → 40936,
  `interrupt` 32012 → 31804, `avs` 32492 → 32448. Two grow — `tenji_int` 32228 → 32336
  and `i2c` 93760 → 94336 — which is inlining trading size for speed where a call was
  worth removing. On the RP2350 the same sample goes 29596 → 29252. The host build takes
  it too, because one `g++` invocation is still not
  one translation unit: all 24 host programs print byte-for-byte what they printed
  before.

  **The Arduino core and the CubeMX project do not get it here.** The Arduino core owns
  its own compile options and offers no way to add one, which is the same delegation seen
  from the other side. The CubeMX build does not link on this desk at all, before this
  change or after, so there was nothing to measure and nothing was changed for it.

## What it costs

Several mechanisms here are worth what they cost rather than free, and these figures are
what makes each one a choice rather than a default.

### What a peripheral costs when nothing names it

Each standard class became a gem with a translation unit of its own, so a program links
only the peripherals it actually names. The Mega 2560 shows it plainly, because it has no
`--gc-sections` doing the same work invisibly: `samples/heartbeat.rb` lights the on-board
LED and never touches a pin, and it went **4190 B → 3496 B → 2702 B of flash** as `GPIO`,
then the rest, left the always-linked file, and **657 B → 186 B of SRAM** once `Serial`
stopped being linked into a program that never prints. Roughly a third of the original
build was machinery for classes the program does not name. The Pico builds are unchanged.

### What exceptions cost

`--no-exceptions` drops the exception mechanism: `begin` becomes a compile error and
the unwinder and its tables are left out. On a `raspberry-pi-pico` build of
`samples/blink.rb` that is 15536 B of text against 10984 B, so the mechanism costs
4552 B of flash and 316 B of RAM even in a program that never raises. Those two figures
are exactly what the same pair cost under pico-sdk 1.5.1 (13236 B against 8684 B): the
mechanism's price is the compiler's, not the SDK's.

A program that actually raises pays far more. `bareruby_throw` pulls in the C++ ABI, and
with it the terminate handler's name demangler and malloc: `samples/m25.rb` comes to 76068 B
of text. That is why the throw lives in its own translation unit and is linked only into
programs that reach it — `--gc-sections` cannot remove it once it is compiled in.

### What an arena and a variable-length string cost

An arena is the other thing here that is worth what it costs rather than free. The same
six statements written twice — once against `Array.new(3, 0)`, once against `Arena::Array.new(3)`
inside an arena block — come to 8364 B of text with the fixed-capacity array and 37036 B
with the arena, both under `--no-exceptions`. The 28 KB between them is the exhaustion path:
running out reaches `bareruby_panic`, and `fprintf` plus `exit` bring stdio with them. With
exceptions enabled the same pair is 12884 B and 90604 B, and the further 50 KB is the
guard — a scope holding an object with a destructor gives its function a cleanup landing
pad, which references `__gxx_personality_v0` and drags in the same C++ ABI a `raise`
does. Releasing the region when an exception leaves the block is what that buys.

Those arena and string figures were taken against the earlier design, where an arena was an
object a program named and passed. **They have not been re-measured since it became a form.**
What moved is where the handle lives and how the block is entered, not what the region costs,
so the comparison they draw should still hold — but nothing here has confirmed that.

A variable-length string adds almost nothing to what the region already costs: six
statements that create one, append to it twice and print it come to 37244 B of text under
`--no-exceptions`, against the 37036 B the arena array's six cost above. The allocator and
its panic path are what both are paying for. The interpolation form is the part worth
counting — `Arena::String.new("readings: #{count}")` makes `vsnprintf` reachable and takes the same
program to 43908 B, where that interpolation assigned to a fixed-capacity local costs
17784 B and no region at all. (Those six figures come from throwaway programs that were
never committed, and are the one set here still carrying its pico-sdk 1.5.1 measurement —
what they compare is two ways of writing the same thing, which the SDK move shifts
equally.) `samples/string.rb`, which uses every form, is 46780 B of text and 3344 B of
`bss`, 1792 of which is the three regions it declares.

### What the M3 samples come to

`samples/uart_receive.rb` is 40004 B of text and 1812 B of `bss` under
`--no-exceptions`; its region accounts for 256 B of the latter. The receive path therefore
fits beside the arena and string runtime without introducing another large dependency.

`samples/i2c.rb` is 40756 B of text and 1808 B of `bss` under `--no-exceptions`, and its
`.uf2` is 73728 B. That includes mixed-output flattening, a write, and a register-select
write followed by a repeated-start read.

`samples/nilable.rb` is 39308 B of text and 1680 B of `bss` under `--no-exceptions`;
its `.uf2` is 70656 B. The sample includes the arena and variable-length string runtime,
so the tagged representation and its control flow fit within the cost already established
for those M3 facilities.

### What `--debug` costs

`-d` / `--debug` turns on USB stdio on a freestanding target, which is what lets `puts`
reach a serial port and the board stay enumerated while the program runs:

| | default | `--debug` |
| --- | --- | --- |
| `.uf2` | 23040 B | 53248 B |
| `text` (flash) | 15536 B | 30596 B |
| `bss` (RAM) | 1484 B | 3604 B |

### What blink comes to on both Pico boards

Measured on both boards from the same first stage:

| Property | `raspberry-pi-pico` | `raspberry-pi-pico2` |
| --- | --- | --- |
| `.uf2` size | 23040 B | 22016 B |
| UF2 family id | `0xE48BFF56` (RP2040) | `0xE48BFF57` (RP2350 Arm-S) |
| UF2 target address | `0x10000000` (XIP flash base) | `0x10000000` (XIP flash base) |
| `text` / `data` / `bss` | 15536 B / 0 B / 1484 B | 14768 B / 0 B / 1100 B |

`arm-none-eabi-objdump -d bareruby_program.elf` shows the blink loop as Cortex-M0+
instructions on the Pico and Cortex-M33 on the Pico 2 — the latter reaches for `strd`,
which the M0+ does not have — with `bareruby_main` inlined into `main` on both by the
release build.

### What the on-board LED costs

`samples/heartbeat.rb` — six lines, `OnboardLED.new` and `on` / `off` — built for all
four boards from one first stage:

| | `text` | `bss` | `.uf2` |
| --- | --- | --- | --- |
| `raspberry-pi-pico` | 15336 B | 1484 B | 22528 B |
| `raspberry-pi-pico-w` | **270236 B** | 4172 B | 532480 B |
| `raspberry-pi-pico2` | 14636 B | 1100 B | 22016 B |
| `raspberry-pi-pico2-w` | **267580 B** | 3532 B | 527872 B |

The 255 KB is the radio: its LED cannot be reached without `cyw43_arch_init()`, and that
uploads the firmware the CYW43 runs. It is the largest single cost this repository has
measured, an order of magnitude past the exception mechanism's 4.5 KB, and it buys one
LED. `pico_cyw43_arch_none` is linked only by a wireless target that actually lights the
LED, so a program that does not is unaffected — `samples/blink.rb` for
`raspberry-pi-pico2-w` still links no CYW43 at all.

### What moving from pico-sdk 1.5.1 cost

Everything above is measured under 2.3.0. The 1.5.1 figures are kept here because they
are what M0 through M4 were recorded against, and because the difference is worth
knowing: both sets below are the same commit, the same compiler and the same programs,
built for `raspberry-pi-pico` with only `PICO_SDK_PATH` changed.

| Program | 1.5.1 `text` / `bss` / `.uf2` | 2.3.0 `text` / `bss` / `.uf2` |
| --- | --- | --- |
| `blink.rb` | 13236 / 1476 / 26624 | 15536 / 1484 / 23040 |
| `blink.rb --debug` | 27052 / 3968 / 54272 | 30596 / 3604 / 53248 |
| `blink.rb --no-exceptions` | 8684 / 1160 / 17408 | 10984 / 1168 / 13824 |
| `interrupt.rb` | 14588 / 1496 / 29184 | 17672 / 1508 / 27648 |
| `nilable.rb --no-exceptions` | 37116 / 1672 / 74240 | 39308 / 1680 / 70656 |
| `m25.rb` | 73848 / 1604 / 147968 | 76068 / 1616 / 144384 |
| `i2c.rb` | 92140 / 1836 / 184320 | 94412 / 1848 / 180736 |

2.3.0 costs 2.2 to 3.1 KB more flash across the board and leaves RAM essentially where it
was. The `.uf2` files are nonetheless smaller, which is not a contradiction: `picotool`
packs the image into fewer 512-byte UF2 blocks than the `elf2uf2` in 1.5.1 did — 45 blocks
against 52 for the default blink — so the file shrinks while the program in it grows.

1.5.1 cannot build `raspberry-pi-pico2` at all, so there is no column for it there.

### What building the targets at once is worth

A run used to compile and build one recorded target, then the next. Nothing was shared
between them by then — what they build with is fetched once before any of them start, and
each compiles into a root only it writes — and cmake is given no `-j`, so each build was
occupying one core of a desk with 28 of them. They are now built at the same time, one
process per target.

The four targets in this checkout's record, `ref.rb`, a cold `.bareruby/` each time, on a
28-core desk:

| Run | Wall clock |
| --- | --- |
| `build --jobs=1` (what it did before) | 20.3s |
| `build` (four at once) | 8.6s |

The four builds are 0.2s (host), 0.6s (mega2560), 8.3s (pico1h) and 8.6s (pico2w), so the
run now costs the longest of them rather than their sum. A desk with more boards of the
same kind gains proportionally more; one with a single target gains nothing, which is the
same run it was.

**What is built does not change.** Compiling the same program twice hashes identically
across `.bareruby/`, and `--jobs=1` and the default produce the same artifacts byte for
byte.

### What writing the boards at once is worth, and what it cost to get there

Two Pico boards on one desk — an RP2040 and an RP2350, both running a `--debug` build, so
both reset into BOOTSEL over USB rather than by hand:

| Run | Wall clock |
| --- | --- |
| `flash --jobs=1` | 28.3s |
| `flash`, both from a running firmware | 10 to 14s |
| `flash`, both already in BOOTSEL | 1.6 to 2.6s |

**Finding the board, not writing it, was what stood in the way.** Three things had to be
answered first, and two of them were live defects that only a run writing two boards at
once could show.

1. **A board was followed across its reset by having appeared** — the BOOTSEL board that
   was not there a moment ago. That reads the whole bus to answer a question about one
   board, so two boards reset together could each be handed the other's. It is followed by
   the port it is plugged into instead. A board keeps that; it does not keep its serial,
   which an RP2040 reports as the bootrom's id in BOOTSEL and the flash id once pico-sdk is
   running. Measured across a reset, the port held (`1-1` before and after, ten samples
   either side) while the serial went from `E6625888179C592E` to `E0C9125B0D9B`.
2. **udev's `/dev/disk/by-id` link outlives the board it names.** The kernel hands a node
   name to the next board as soon as the one holding it leaves, and the link published for
   the board that left still points there until udev catches up. Waiting for *any* link to
   resolve to the node is therefore satisfied by the stale one. In a recorded run this put
   an RP2350 target on an RP2040's volume — `Board-ID: RPI-RP2` under the row for the
   RP2350. What is waited for now is the link that names *this* board, resolving to this
   node.
3. **The fstab lookup resolved every line to a device and compared nodes**, which asks the
   same question of the same stale state, so a board could be handed the mount point of a
   board that had left. The line is found by the by-id path that carries the board's own
   serial, compared as text.

**And the volume is asked which chip it is before anything is written to it.** Everything
above identifies a board through the kernel and through udev, and those two are not
published at the same instant. The `Model:` line in `INFO_UF2.TXT` is the board itself
answering, on the volume about to be written; an image for the wrong chip is refused there
rather than written.

### What a moving bus costs the scans, and what that looked like

The first version of the above was reported failing and succeeding in strict alternation,
and the alternation was the clue. A board being written **moves the bus for everything
else on it**: it reboots into its bootloader and back, arriving and leaving as two
different USB devices, and every other board's serial port is renumbered around it. Two
scans were written as though that were not happening.

1. **A scan that trips over a board leaving took the whole run with it.** The scan reads a
   device's serial out of sysfs, and a board that reboots between the line that finds the
   file and the line that reads it makes that read fail. Under `set -euo pipefail` the
   failure left the flasher with no status of its own and nothing said — from outside, the
   flash simply stopped, with no message at all, ten seconds in. **That is what made the
   failures alternate**: a run that died there left the board sitting in BOOTSEL, so the
   next run found it already there, needed no reset, and succeeded — which left it running
   again for the run after that to reset and die on. Every read in the scan now fails into
   "not a board" rather than into an error, which is what the half of it that scans serial
   ports already did.
2. **A board asked for at the wrong moment answers that it is not attached.** The Arduino
   is identified by the serial port it brought up, and `arduino-cli board list` was asked
   once. Asked while a Pico beside it was re-enumerating, it did not report the Arduino,
   and the row failed with `no attached board is arduino:avr:mega` 1.2s in — reliably, on
   every run where the Pico needed a reset. It is asked until the board answers, the way
   every other wait on hardware here is written.

Both were only reachable by writing more than one board at once, and both were found by
running it. Afterwards: six consecutive single-board runs from a running firmware, four
consecutive Pico-and-Arduino runs, and three consecutive runs of all four targets, all
successful.

**What remains is the wait itself.** The boards reach this desk through usbipd, which
re-attaches a board a few seconds after each reset — measured at 5.1s from the board
disappearing to its bootloader arriving. Where that runs past what the flasher waits, the
run says so and stops rather than dying quietly. A desk reaching its boards without usbipd
has less of this to wait for.

### The port is not always the same board, and what that cost

Two boards written at once were reported failing and succeeding in alternation again, and
this time **the two of them came back holding each other's port**. Measured, in one run:
the RP2350 was reset from port `1-1` and the RP2040 from `1-2`, and afterwards each was
looked up under the other's identity — the RP2350's row built an fstab path reading
`usb-RPI_RP2350_E0C9125B0D9B` (the RP2040's bootrom id) and the RP2040's row read
`usb-RPI_RP2_34319CF054AB3BD6` (the RP2350's).

**Off a bus a port cannot do this**: the socket does not move, which is what the earlier
measurement showed for one board resetting alone. usbipd is not a bus — it hands a Windows
device to WSL over a network — and two devices re-attaching at once are given their slots
in whatever order they arrive.

Neither board matched an fstab line under the wrong identity, so both fell back to the one
mount point a desk names for boards it does not know, and both reached for `sudo` to mount
it. **That is where the run stopped forever.** Each board is written in a process whose
output is a pipe, so `sudo` had nowhere to print its prompt and nowhere to read the answer,
and waited for a password that could not be typed at a prompt nobody saw. Run where a
terminal is absent outright it says so and exits; run from one, it waits.

- **`sudo` is reached for only where there is a terminal to answer it.** Otherwise the
  fstab line to add is printed and the row fails.

### An RP2040's bootloader has no name, and what that forced

Five boards on one desk — three RP2040 and two RP2350 — made the rest of it plain.

**The two RP2350s named themselves and the three RP2040s did not.** In BOOTSEL the RP2350s
reported `34319CF054AB3BD6` and `5D3F58054E676E14`, the same serials their firmware
reports. All three RP2040s reported `E0C9125B0D9B` — two of one model and one of another,
identical down to model, revision, `bcdDevice` and size. There is nothing else in sysfs to
tell them apart but the port they are on.

**That broke the mount before it broke anything else.** udev publishes one
`/dev/disk/by-id` link per name, so with three RP2040s attached exactly one of them had a
by-id name and the other two had none. A mount that followed the name therefore reached
whichever board held it rather than the board asked for — **it wrote a board nobody
named**, silently, and reported that the board asked for was still in BOOTSEL. Every
identical board past the first was unreachable.

`/dev/disk/by-path` names a device by the port it is on, exists for every device, and
never collides. The fstab lines are keyed by it, one per port, looked up rather than
spelled out — the prefix is the system's own, a PCI controller on one desk and a virtual
host controller where the boards arrive over usbipd.

### The three things writing a board turned out to be

Following a board across its own reset was the wrong question. It is not followable: its
serial changes or is not unique, and its port is handed out by arrival order where a
transport rather than a bus is carrying it. **What is followable is nothing — so nothing
is followed.** Every board is reset, the bus is given up to 100s to settle, and everything
on it is looked at once, on a bus that has stopped moving. Only then is anything written.

| | | measured |
| --- | --- | --- |
| reset | in turn | 0.036s for two boards — nothing worth doing at once |
| settle | once, shared | 11 to 21s here; 100s allowed |
| find | once, centrally | one listing |
| write | all at once | 1.7 to 3.6s a board |

**Two identical boards taking one image are written at the same time**: 2.7s against the
10.1s the same pair took in turn. That is the case a shelf of identical boards is, and it
needs no identification at all — the boards take the same image, so any one-to-one
handing-out of them is right, and the finding was done centrally so there is exactly one.
Two entries that would each take every board of a chip are the one thing left that no
image can settle, and that is put back to the record rather than guessed at.

Four runs of every target afterwards — five boards written across them — went 4/4, 3/4,
4/4, 4/4, each with the right image on the right chip. The one failure was a board usbipd
had not brought back inside the settle. **The alternating failures are gone**: a run that
starts with a board already in BOOTSEL now succeeds like any other, and the run after it
succeeds too.

### A board that says its own name

Everything above works around a board having no name. The way out is to give it one.

`bareruby target attach` writes the target entry's own name — `pico1h`, `pico2` — into a
page of the board's flash, and the firmware reads it back and hands it to the host as its
USB serial number. Windows files the board under it (`USB\VID_2E8A&PID_000A\PICO1H`), Linux
publishes it in sysfs, and two Pico 1 boards of the same model, which had nothing between
them, became `pico1h` and `pico1b`.

Four things had to be true for that, and all four were measured rather than assumed.

- **The name is data, not code.** It is the first page of the last flash sector —
  `0x101FF000` on a 2 MB Pico, `0x103FF000` on a 4 MB Pico 2 — which no image comes near:
  the largest measured here is 553 KB. So one firmware serves every board, and every
  program flashed afterwards keeps the name.
- **The descriptors have to be the program's own.** pico-sdk wraps its whole descriptor
  file in `PICO_STDIO_USB_USE_DEFAULT_DESCRIPTORS`, so setting it to 0 hands the three
  callbacks over. The vendor and product ids are kept exactly as the SDK writes them: the
  flasher tells an RP2040 from an RP2350 by the product id. **Cost: 72 bytes of `text` and
  44 of `bss` on an RP2040, 80 and 44 on an RP2350 — the `.uf2` did not change size.**
- **The page travels with a firmware, and that firmware is the binding's own.** A page
  written by itself would reboot the board into the unnamed firmware it already had —
  needing the board found a second time, which is the problem this exists to end. So
  `target attach` writes the *agent* beside it: a resident firmware that brings USB up,
  says the name and waits for the next program on core 1, the same one for every board of
  a machine, costing 29272 bytes of `text` on a Pico and 29264 on a Pico W. **No program
  of the user's is in this** — programs are what `deploy` and `flash` carry, and they keep
  the name when they arrive. The page goes first in the file, announcing two blocks and
  supplying one, so the download stays open until the agent's blocks replace it; pico-sdk
  plays the same trick with the block it puts in front of an RP2350 image.
- **An RP2350 wants the family id that means "an address".** Given the page under
  `e48bff59`, the family its own program carries, the bootloader wrote the program and
  **silently dropped the page** — the board came back reporting `34319CF054AB3BD6` as
  before. Under `e48bff57`, which says the block belongs to no image and goes where it
  says, it came back as `pico2`. An RP2040 has no such id and needs none: it has no image
  rules for a loose page to be outside of.

The resident replacement path was then made complete rather than inferred from its first
acknowledgement. The standalone agent had brought USB up but had never started the core-1
listener, and the first mover that did receive an image could be inlined back into flash,
return into the image it had erased, and call the flash-resident watchdog routine. The
agent now starts the listener; the mover is explicitly no-inline in RAM, copies without a
library call, and triggers the watchdog from its RAM-resident tail. Its generated RP2040
and RP2350 ELFs put the mover and both flash operations at `0x200...`, rather than in the
image being replaced.

Two host-side boundaries mattered too. An RP2350 UF2 begins with absolute-family metadata
at `0x10ffff00`; only its `e48bff59` program-family blocks are streamed. And `BRDONE` means
the bytes have arrived, not that the 200 ms delayed reboot has happened, so the host now
requires the old port to disappear and the same name to return before it reports success.
Without that edge, immediately repeated runs alternated between apparent success and no
board.

`flash` also has to mean the last successful build after the compiler has done unrelated
work. Its first version read the compiler's working directory, which every later `compile`
or `build` clears; the artifact still plainly existed in `build/<target>/`, but flashing
raised `ENOENT`. Each successful build now keeps the artifact and its manifest per entry
under `.bareruby/flash/`, leaving public `build/` as one artifact per entry while making a
later flash independent of compiler scratch state.

On hardware, one Pico completed five successive streamed replacements, and two identical
Picos named `pico1h` and `pico1b` completed five successive parallel runs, 2/2 each, in
16.8 to 17.4s under WSL. The ports were renumbered between runs; the names and the images
did not swap. A Pico W was then attached as `pico1w` and took its 37888-byte Pico W image
over the same resident path five times. The last came after all 30 representative sources
had been compiled and the compiler working tree cleared on every run, without the Pico W
being confused with either plain Pico or losing the last built image.

**BOOTSEL is what says which board, and only the first time.** Before a board carries a
name there is nothing that could say it, so the choice is a button held by hand; afterwards
it never has to be made again.

**What it costs under WSL is one more `usbipd bind` per board.** Windows files a USB device
under its serial number, so a board that has just been named is one it has never seen.

The same entry can now own a shelf rather than one board. Repeated
`target attach --target=pico1` runs assigned `pico1`, `pico1-2`, and `pico1-3` and appended
all three to one `boards:` list. Two single-board assumptions had survived the earlier
work: device selection returned the board matching the entry name before consulting the
explicit list, and preparation trusted only that first board's resident listener while
resetting the suffixed boards into BOOTSEL. The list is now authoritative in both places,
so every listed running board is selected and streamed to without losing its name.

That boundary matters on the RP2040 hardware measured here: all three ROM bootloaders
reported `E0C9125B0D9B`, so two reset together cannot be distinguished reliably by the
Windows USB stack. With all three running as `pico1`, `pico1-2`, and `pico1-3`, one
`deploy --target=pico1` sent the same 29184 bytes over three CDC ports in parallel. The
flash stage took 7.0s, the complete build-and-deploy took 14.5s, and all three names were
present again afterwards. The CDC 1200-baud reset remains available, while the unused
vendor reset interface is omitted; each running board now presents two interfaces rather
than three.

The next names begin at `_01` rather than leaving the first board unsuffixed: a fresh
`pico1` entry grows `pico1_01`, `pico1_02`, `pico1_03`. Existing lists still determine the
next number by their length, so a desk already carrying the earlier spellings does not
reuse a number while it is being changed over.

The running USB descriptor now says `BareRuby Debug Firm RP Pico1 (<board name>)`, or
`RP Pico1W`, `RP Pico2`, and `RP Pico2W` for the other machines, while keeping the SDK's
vendor and product ids and the attached name as the serial. Four connected RP2040 boards
— three Picos and one Pico W — accepted those images in one parallel deploy and all four
returned on CDC as `pico1_01`, `pico1_02`, `pico1_03`, and `pico1w_01`.
After separating USB identity from the resident updater and making its acknowledgement
wait tolerate quiet intervals, the final run sent 38656 bytes to each Pico and 287744
bytes to the Pico W, completing both target rows in 29.6s.

Windows records that exact product in `DEVPKEY_Device_BusReportedDeviceDesc`, but
`usbipd-win` does not print it for a CDC composite device: its list deliberately combines
the friendly names of the direct children instead, which are the Windows USB serial
driver's `USB Serial Device (COM...)` names. Reporting the device itself as vendor-specific
removed that composite classification, but Linux then did not bind `cdc_acm`; the serial
path disappeared and resident deploy could not finish. That experiment was reverted. The
exact firmware descriptor and four-board CDC deployment are therefore proved; making the
current `usbipd list` column use it is a Windows host-tool change, not another firmware
descriptor.

Copying each bound device's `DEVPKEY_Device_BusReportedDeviceDesc` into usbipd-win's saved
`Description` made that host-tool change without touching the device. Its connected list
then read `BareRuby Debug Firm RP Pico1 (pico1_01)`, `(pico1_02)`, `(pico1_03)`, and
`BareRuby Debug Firm RP Pico1W (pico1w_01)` for the four boards. All remained attached at
the same Windows bus ids and appeared in WSL as four distinct `ttyACM` devices. The copy
needs one Administrator PowerShell run after newly named devices are bound; it is recorded
in the README rather than hidden as a firmware result.

### Four boards with one id, told apart by where they are

`target attach` had one way of being told which board was being named: the BOOTSEL
button. That answer is invisible, cannot be taken back, and stops being an answer the
moment two boards are held at once — which the flasher refuses rather than guesses at.
Four Pico 1 boards were put in BOOTSEL together to see what there was to tell them apart
with:

```
SERIAL             CHIP     STATE    DEVICE         LOCATION   FIRMWARE
E0C9125B0D9B       rp2040   bootsel  /dev/sde1      7-1        RP2 Boot
E0C9125B0D9B       rp2040   bootsel  /dev/sdf1      7-3        RP2 Boot
E0C9125B0D9B       rp2040   bootsel  /dev/sdg1      8-4        RP2 Boot
E0C9125B0D9B       rp2040   bootsel  /dev/sdh1      7-4        RP2 Boot
```

**One serial across all four** — the bootrom's own id, not a name anybody chose. Four
block devices, whose names are the order they happened to be scanned in. And four places,
each of which belongs to one board. So the place is what a person is offered, and
`target attach` asks instead of reading a button: the entries down the left, the boards
that entry could take down the right, and a confirmation before anything is written.

**Where a board is is not one number.** These arrive over usbipd, so the kernel's own port
path names a virtual controller and appears nowhere on the Windows side, where the board
is `7-1` in `usbipd list` and in the `usbipd attach --busid 7-1` that handed it over. The
vhci hub's status table carries the far side's device id — `00070001`, a bus number over a
device number — so `7-1` is read back out of the kernel rather than by running a Windows
program once per listing and matching on a serial all four boards share. Boards on two
different Windows buses (`7-1`, `7-3`, `7-4` and `8-4`) were resolved in the same pass.

The board at `7-1` was then named through that screen. It took 17.6s, nearly all of it
building the agent for the entry, and the board came back as `2e8a:000a`, filed by Windows
under `USB\VID_2E8A&PID_000A\PICO1H_02` and reporting `BareRuby Debug Firm RP Pico1
(pico1h_02)` as its bus-reported description. `config/target.yml` went from
`boards: [pico1h]` to `boards: [pico1h, pico1h_02]` on its own, and the next run of the
screen offered `pico1h_03` to the three boards still sitting in their bootloaders.

**And it reads back as itself — after being handed over a second time.** A freshly named
board re-enumerates as a device usbipd has never seen, so it returns `Not shared` and is
out of WSL's reach entirely; the listing does not show it wrongly, it does not show it at
all. Bound and attached again, it reads

```
SERIAL             CHIP     STATE    DEVICE         LOCATION   FIRMWARE
pico1h_02          rp2040   running  /dev/ttyACM0   7-1        BareRuby Debug Firm RP Pico1 (pico1h_02)
```

The serial is the name, and the firmware column carries the name as well — the string
sysfs publishes is the agent's own product string, parenthesis included, rather than
anything the Windows side composed. The screen no longer offers this board: it is running
rather than sitting in a bootloader, and the record holds its name.

**What the chip cannot say, this cannot say either.** A Pico and a Pico W are both rp2040,
so all four are offered under a `pico` entry, the Pico W among them. The button never told
them apart either; what has changed is that the four are on screen, where somebody who
knows which is which can point at one.

### Two functions, because one of them is only there to be named

The firmware was a single CDC ACM function wearing a composite's clothes: TinyUSB's CDC
template opens with an Interface Association Descriptor, and pico-sdk's device descriptor
says `ef/02/01` to match, which is what a device says when it is a container of
associated functions. It was not one. Nothing had decided that — it was the toolkit's
default, copied along with the descriptor set when this side took the descriptors over to
put the board's name in them.

**What that cost was the name on Windows.** Linux reads a device's own product string:
`lsusb` prints `2e8a:000a Raspberry Pi BRDF pico1_09` and has always done so. Windows
names a device after the driver that claimed it, and for a composite it names each child
after that child's driver — so a CDC board reads `USB シリアル デバイス (COMxx)`, the same
sentence for every one of them, and `usbipd list` shows that copy. Four named boards on a
desk were indistinguishable in the one place a person looks before handing one to WSL.

Declaring the truth was measured first: `bDeviceClass = 02/00/00` with the association
dropped. Windows stopped loading `usbccgp` (`Service: usbser`, `USB\COMPOSITE` gone from
the compatible ids, no children), Linux bound `cdc_acm` to both interfaces exactly as
before, and `/dev/ttyACM*`, resident deploy and program output were all unaffected. **It
did not fix the name**: with no children, Windows named the device itself after `usbser`,
which is the same sentence one level up.

**The chip's own bootloader shows the way out.** It is two functions — mass storage and
PICOBOOT — and the second has no Windows driver, so Windows has nothing of its own to
call it and falls back to the device's product string. That is the whole of why
`usbipd list` reads `USB 大容量記憶装置, RP2 Boot` and not `USB 大容量記憶装置` alone. The
firmware now carries a second interface for the same reason: vendor class, `iInterface`
0, endpoints declared so TinyUSB can claim it, and **nothing sent or received on it
ever**.

```
8-4  2e8a:000a  USB シリアル デバイス (COM37), BRDF pico1_09   Attached
```

Measured beside boards still carrying the older firmware, in the same table:

```
PICO1_05  |  USB シリアル デバイス (COM33)
PICO1_08  |  USB シリアル デバイス (COM36)
PICO1_09  |  USB シリアル デバイス (COM37), BRDF pico1_09
```

No privileged step is involved: usbipd takes the description when it binds the board, the
way it does for anything else. The Administrator PowerShell that used to copy each board's
reported product into usbipd's saved record is gone with it.

On Linux nothing changed. The interface has no driver, so no device node is made for it,
and the serial port is the `dialout`-owned `/dev/ttyACM0` it always was — no udev rule, no
raw USB, no new dependency.

**The product string was cut down to fit.** `BareRuby Debug Firm RP Pico1 (pico1b_02)` is
40 characters, and Windows prepends 27 of its own before it; the DEVICE column is 60 and
the name — the only part worth reading — was what fell off the end. `BRDF <name>` is 14.
"Debug Firm" was saying nothing, because a board with no USB interface at all is what the
other build is, and the model was already in the name a desk gave the board. The
per-machine product strings went with it.

**What was tried and taken out.** Carrying BRDF itself on that second interface was
implemented and reverted. It closes a real hole — a program printing `BRDONE` can answer
for the board, because the transfer shares the serial stream with the program's own
output — but reaching an interface no kernel driver claims means raw USB, and raw USB on
Linux means a udev rule on every desk, forever. `picotool` ships one for exactly these
four product ids, so it is the ordinary price of that road rather than anything unusual.

**And what ruled it out is not arithmetic.** These commands exist to take work off the
person using them, and that is the whole of what they are for: `target add` asks rather
than sending somebody to look a triple up, `attach` names a board so that nobody reads a
serial again, `build` fetches its own toolchain, `deploy` reaches a board without the
button. A feature that hands a privileged step back — one every desk performs, before
anything works, forever — is not a cost to be set against a benefit. **It works against
the reason the commands exist.** That it buys something real does not save it; a
correctness that is paid for in `sudo` on somebody else's machine is not this ecosystem's
to spend.

The hole stays open knowingly: this is the debug build, on a desk, being written to by the
person who wrote the program.

Cost: `2.5 KB` of `.uf2` for the second interface (76.0 → 78.5 KB on a Pico 1). Carrying
the transfer on it as well had cost 9 KB more, and that is gone with it.

## Verified on hardware

These are runs on real boards rather than successful builds. The flashing route each one
took is described in the [README](README.md#flashing-a-pico).

### Raspberry Pi Pico

Verified end to end. With a default build, `2e8a:0003`
disappears from `lsusb` after flashing and GP25 (the on-board LED) blinks at the
500 ms period written in `samples/blink.rb`; the board presents no USB interface at all,
which is correct with both stdio channels disabled, and the button is needed to flash
again. With `-d` it comes back as `2e8a:000a` with a `/dev/ttyACM0`, and successive
edits were flashed by rerunning `bareruby flash` alone — verified by changing the blink
period to 100 ms and then 800 ms and watching the LED follow.

### Pico 2 W

Verified again on a **Pico 2 W**, which is an RP2350 board. `flash.sh` wrote the
`raspberry-pi-pico2` image (`Model: Raspberry Pi RP2350`, `Board-ID: RP2350` out of the
bootloader's `INFO_UF2.TXT`), the board left BOOTSEL and came back as `2e8a:0009` with a
`/dev/ttyACM0`. A `-d` build of

```ruby
counter = 0

loop do
  counter += 1
  puts "bareruby on rp2350: #{counter}"
  sleep_ms(500)
end
```

printed to that port continuously — 20 lines in 10 seconds, the counter advancing by 19,
which is `sleep_ms(500)` keeping time on the hardware. Ruby to BRAST to TAST to LIR to
C++ to an RP2350 running the result.

The LED is the part worth recording. `samples/blink.rb` was flashed onto the same board,
and a variant logging each write showed `gp25 high` / `gp25 low` alternating once a
second on the serial port while **the LED stayed dark the whole time**. The writes reach
GP25; on a Pico 2 W the LED is not there. Both boards then took the same `samples/blink.rb`
from one `bareruby deploy` invocation, and the Pico blinked while the Pico 2 W did not.

`samples/heartbeat.rb` closes that gap and was flashed onto both. The Pico blinks at the
100 ms on / 900 ms off it asks for, reaching its LED through GP25; the Pico 2 W blinks
the same way, reaching its LED through the radio. One program, two routes, and the
program names neither.

### From a macOS host

The same route was verified from **macOS** rather than Linux or WSL — Apple silicon,
macOS 15 — on a Raspberry Pi Pico. Nothing in the build had to change: the darwin-arm64
cross toolchain and pico-sdk 2.3.0 come from the same pinned `sources.lock.yml`, and
`raspberry-pi-pico` built through to a `.uf2` unmodified.

`flash.sh --list` found the board through `ioreg` — `E0C9125B0D9B rp2040 bootsel
/dev/disk4s1` — and the volume macOS had already mounted at `/Volumes/NO NAME` answered
`UF2 Bootloader v3.0`, `Model: Raspberry Pi RP2`, `Board-ID: RPI-RP2`. A `-d` build of
`samples/blink.rb` (52736 bytes) was written from BOOTSEL, after which the board came back
as `E6658C344B689A25 rp2040 running /dev/cu.usbmodem1201`: the flash id against the
bootrom id, the two-serial behaviour Linux shows, seen here too. The default build
(22528 bytes) was then written **without the button**, over the 1200-baud reset, and GP25
blinked at the 500 ms period `samples/blink.rb` asks for. Afterwards `--list` reports
nothing attached, which is correct for a default build.

One thing macOS makes worse rather than easier: a board whose mass storage has stopped
replying makes `diskutil` and `system_profiler` hang uninterruptibly, past `kill -9`,
because both walk the device to answer. Everything the flasher asks about hardware goes to
`ioreg`, which reads the kernel's registry and returns whatever the bus is doing.

### Which targets have actually run

The STM32 target is now built by the `arm-none-eabi-g++` the
[README](README.md#versions-this-was-verified-against) lists, the same one
the Pico boards use. The hardware runs recorded here came before that: their translation
units and ELF were built with STM32CubeIDE's GNU Tools for STM32 14.3.1, and headless
build, SWD programming, LD2, and USART2 were verified on a
physical NUCLEO-F446RE. I2C was linked against STM32CubeF4 HAL 1.28.3 but has not yet
been exercised with an external device.

The Pico hardware run was done under pico-sdk 1.5.1, which is what the repository used at
the time; the Pico 2 W run and the two-board run were done under 2.3.0.

Of the four Pico board targets, **`raspberry-pi-pico` and `raspberry-pi-pico2-w` have run on
real hardware**; `raspberry-pi-pico-w` and `raspberry-pi-pico2` are built but not run,
because neither board is here.

`arduino-mega2560` has run on real hardware as well. `samples/heartbeat.rb` blinks the
board's LED at the 100 ms on / 900 ms off it asks for; `samples/features.rb`,
`samples/fixed.rb` and `samples/string.rb` printed over the board's serial port and were
compared line for line against the same programs run on the host, and against real Ruby
where the two are meant to agree; and `samples/logger.rb` said `logger ready` through
`uart.puts` and then said nothing for six seconds, which is a pulled-up input reading
high some sixty times. The board is an ELEGOO MEGA 2560 R3 rather than the Arduino it
copies — the same chip, the same bridge, and Arduino's own vendor and product ids, so
nothing between the Ruby and the flash can tell the two apart.
