# Arduino core binding

The Arduino core is one surface to call — `digitalWrite`, `Serial`, `Wire`, `analogRead` —
spread over boards that share no instruction set: AVR, SAMD, nRF52, RP2040 and ESP32.
That is why the instruction set is named separately from the binding: one `binding.rb`
serves all of them, and `machine/` carries what each board is called.

The core owns `main` and calls `setup` and `loop`, so this binding supplies those rather
than an entry point of its own, and its `PROGRAM_FILE` is named after the program.
`arduino-cli` builds it, selected by the FQBN each machine records.

`arduino-mega2560` is the board this was proved on, an ATmega2560 at 16 MHz with 256 KB
of flash and 8 KB of SRAM. The one on the desk is an ELEGOO MEGA 2560 R3, which carries
the same chip and the same USB-serial bridge and answers to Arduino's own vendor and
product ids, so nothing on this side can tell it from the board it copies.

## What arduino-cli takes

Not a build file — a directory. A sketch is a directory holding a file of its own name,
and everything beside that file is compiled with it; nothing outside it is. So the
declaration the first stage makes everywhere — *these are the translation units this
program reached for* — is met here by gathering exactly those into one directory.
`toolchain.rb` copies the sources the manifest names, and the headers whole because every
program uses them, into `bareruby_program/` and hands that over. The link boundary
survives a build system this side does not own: a program that never touches I2C leaves
`Wire.h` unmentioned, so the library is never even discovered, let alone linked.

The sketch that comes out is a complete one. It can be opened in the Arduino IDE and
built there without this repository.

## What this core cannot be asked for

- **PWM has a duty and nothing else.** `analogWrite` picks its frequency from whichever
  timer the pin sits on and offers no way to name another, so `PWM.new(pin,
  frequency: 50)` is remembered rather than obeyed and `pulse_width_us` is turned into
  the duty it would be at the frequency that was asked for. A servo needs the chip's
  timer registers, which is no longer this core's vocabulary.
- **No pull-downs.** The chip has pull-ups only, so a pin asked for the other is left
  plain.
- **No exceptions.** The core compiles with `-fno-exceptions` and this libc carries no
  unwinder, so `begin` has nowhere to land: a program that uses it has no build for this
  board either way round. `--no-exceptions` is what the first stage should be told, and
  it is not a choice here the way it is on a Pico.
- **The receive queue's size is the core's.** `HardwareSerial` declared that buffer and
  fills it from its own interrupt, so this binding buys no second one — which also means
  `UART.new(..., rx_buffer_size: 512)` is asking this board for something it cannot give.
  The build stops on it rather than running quietly with a different size. Saying nothing
  gets `SERIAL_RX_BUFFER_SIZE`, which is 64 bytes on an ATmega2560.
- **`%lld` is not implemented** by this libc's `printf`. Interpolating an `Int64` prints
  the line up to that point and stops.

## Where a word is 16 bits

This is the first machine here whose natural word is not 32 bits, and it found three
things that every 32-bit target had been hiding. All three are fixed in code shared by
every target, because all three were wrong everywhere and only visible here.

- **A conversion names a width, not a language type.** `int32_t` is an `int` on a 64-bit
  machine and a `long` on this one, and a value crossing an ellipsis is not converted to
  a parameter's type because there is no parameter. So an interpolation renders as `%ld`
  and pass 12 widens the value to `long`, which is 32 bits on both. With `%d`,
  `"count=#{70000} step=#{7}"` printed `count=4464 step=1` — the low half of the first
  value, and then the high half read as the second.
- **`1 << 15` is a shift into the sign bit** when an `int` is 16 bits. The half added
  before `Fixed`'s rounding shift was subtracted instead, and `(0.5 * 100).to_i32`
  answered 49.
- **A `*` field width is not read** by the smallest `printf` a machine ships with, so a
  width handed over as a value never arrives. `Fixed#to_s` now carries one format per
  fraction width.

None of the three is an eight-bit problem. They are what a 32-bit machine agrees with by
accident, and this board is where the accident stopped.
