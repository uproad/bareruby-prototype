# Arduino core binding

The Arduino core is one surface to call — `digitalWrite`, `Serial`, `Wire`, `analogRead` —
spread over boards that share no instruction set: AVR, SAMD, nRF52, RP2040 and ESP32.
That is why the instruction set is named separately from the binding: one `binding.rb`
serves all of them, and `machine/` carries what each board is called.

Two boards are reached here, and they share nothing but that surface. `arduino-mega2560`
is an ATmega2560 at 16 MHz with 256 KB of flash and 8 KB of SRAM, whose natural word is
16 bits; the one on the desk is an ELEGOO MEGA 2560 R3, which carries the same chip and
the same USB-serial bridge and answers to Arduino's own vendor and product ids, so nothing
on this side can tell it from the board it copies. `freenove-esp32-s3-wroom-arduino` is an
ESP32-S3-WROOM-1 N16R8 module, two Xtensa LX7 cores at 240 MHz with 16 MB of flash, whose
serial port comes out twice and whose indicator is one addressable RGB device.

**That second board is reached by another binding too**, through ESP-IDF, and that is the
reason it is here. Which SDK answers for a board is a separate question from which board
it is: the machine is one, the two compositions are two, they build different firmware
into directories of their own, and a program says nothing about either. The board's own
numbers — its indicator's pin, its two buses, the pins its serial lines come out on — are
the same numbers in both, because they are facts about the board rather than about either
SDK.

The core owns `main` and calls `setup` and `loop`, so this binding supplies those rather
than an entry point of its own, and its `PROGRAM_FILE` is named after the program.
`arduino-cli` builds it, selected by the FQBN each machine records.

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

**Which core is fetched follows from which boards a run is for.** The AVR core is 259 MB
and the ESP32 one is 5.6 GB, and both are somebody else's compiler, so a desk is not asked
to hold the one it has no board for. The first two words of an FQBN are the packager and
the architecture, which is exactly what `core install` takes — so which core a board wants
is already written in what this side calls that board, and no second list says it again.
A core Arduino did not publish needs the index that lists it, which the lock carries.

## Where a board's own facts live

Every pin this binding needs a number for arrives from `machine/` as a definition the
build hands the compiler, rather than as a number written into a unit — the indicator's
pin, the two I2C buses, the pins each serial line comes out on, the transmit pin a break
is sent by taking back. So are the converter's width and what it reads at full scale,
which are as much a fact about a board's wiring as about its chip. The units are written
in terms of the names, so the next board through this binding is a file in `machine/` and
nothing else.

## Where the core does not spell a peripheral the same way

One implementation of each peripheral serves both boards, which is the whole claim this
binding makes. It is not quite true, and where it stops being true is worth knowing.

- **`setup` and `loop` are C symbols on one core and C++ symbols on the other.** The AVR
  core declares them inside `extern "C"`; the ESP32 core declares them as C++. Neither is
  this side's to choose, and a program written for the wrong one links against nothing.
- **`printf` has somewhere to go on one and not the other.** This AVR libc has no stream
  until one is made, so one is made over the console port; on an ESP32 the console is a
  UART the system opened before any of this ran.
- **The frame is one number, and it is not the same number.** An AVR lays the three fields
  out as separate bits of one byte and an ESP32 lays them out differently in a word with a
  marker above them, so the byte a line is opened with is built twice.
- **A line is opened on pins that can be moved, on one of them.** An AVR reaches a USART's
  own pins and cannot be told others; an ESP32 has to be told, and is told the board's.
- **What a frequency means to `analogWrite` is not the same.** See below.

Everything else — `pinMode`, `digitalWrite`, `analogRead`, `attachInterrupt`, `Wire`,
`HardwareSerial`, `delay` — is one implementation, and the board's numbers are what it
differs by.

## What this core cannot be asked for

Some of these are one board's and some are both boards'.

- **No hardware flow control, on either.** A line asked for with RTS/CTS is refused rather
  than opened without it.
- **PWM has a duty and nothing else, on the AVR.** `analogWrite` picks its frequency from
  whichever timer the pin sits on and offers no way to name another, so `PWM.new(pin,
  frequency: 50)` is remembered rather than obeyed and `pulse_width_us` is turned into the
  duty it would be at the frequency that was asked for. A servo needs the chip's timer
  registers, which is no longer this core's vocabulary. **On the ESP32 the frequency is
  obeyed** — each line takes a channel whose frequency is settable — but the duty is still
  eight bits, so a servo's pulse is quantised to a 78 µs step at 50 Hz.
- **No pull-downs on the AVR.** The chip has pull-ups only, so a pin asked for the other is
  left plain. The ESP32 has both, and the core says which by whether it defines the mode at
  all.
- **No exceptions on the AVR.** That core compiles with `-fno-exceptions` and this libc
  carries no unwinder, so `begin` has nowhere to land: a program that uses it has no build
  for that board either way round. **The ESP32 core is built with them**, so `begin`
  works there and `--no-exceptions` decides something — though not a size: the unwinder is
  in libraries the core ships already built with it, so what the flag leaves out is the
  tables for this side's own translation units and nothing more.
- **The receive queue's size is the core's, on the AVR.** `HardwareSerial` declared that
  buffer and fills it from its own interrupt, so this binding buys no second one — which
  also means `UART.new(..., rx_buffer_size: 512)` is asking that board for something it
  cannot give. The build stops on it rather than running quietly with a different size.
  Saying nothing gets `SERIAL_RX_BUFFER_SIZE`, which is 64 bytes on an ATmega2560. **On
  the ESP32 the driver is told a size before the line is opened**, so the number is given
  to it and honoured.
- **Two serial lines on the ESP32**, which is what that board wires up, against four on the
  Mega.
- **`%lld` is not implemented** by the AVR libc's `printf`. Interpolating an `Int64` prints
  the line up to that point and stops.
- **The ESP32's converter is not calibrated.** `analogRead` is twelve bits scaled over the
  3.1 V the core's default attenuation reaches, which is also the least linear of them.
- **No PSRAM.** The module carries 8 MB of it and nothing here asks for it.

## What a board is given

A Mega takes one image and `arduino-cli upload` writes it.

An ESP32 takes four — a bootloader, a partition table, an OTA selector and the program,
each at its own offset — and the build says which offset each goes to, in a file of its own
beside them. Everything downstream of a build here is one artifact, so the four are merged
into the single image those offsets describe and writing a board is one file at offset
zero. **The offsets stay the core's answer**: they are read out of what it wrote rather
than copied onto this side.

**Which port, and which reset.** A board of that family can bring its serial port out
twice: through a USB-to-serial bridge, and through the chip's own USB peripheral. Only the
second answers a request to be written on this board, and it needs no auto-reset circuit
and no button held — but the only reset that can be driven over it is its own, and the chip
takes that as another request to be flashed. `arduino-cli upload` asks for the ordinary
hard reset and offers no way to say otherwise, so a board written by it comes back still
waiting to be written, with the program that was just given to it sitting unread in flash.
That is why a core whose lock names its own writer is written by that writer instead: the
same four images at the same offsets, merged, and then a reset from underneath the
peripheral, which boots what was just written. A bridge chip holds the reset pin itself and
takes the ordinary one.

**The port is found rather than named.** `arduino-cli` is asked which of this desk's ports
carry a board this firmware was built for, and `boards:` in `target.yml` names one only
when that answer is more than one. How much of a name a board answers with is the core's:
an AVR board carries a USB id of its own and is recognised as itself, three words deep,
while every board of the ESP32 family brings up one and the same USB device — so what a
port answers there is the family, and which board of it this is, the bus cannot say. On a
board whose two sockets are both attached that is exactly enough: the bridge is not a
candidate, and the port that can be written is the one that is found.

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
