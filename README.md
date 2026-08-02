# bareruby-prototype

BareRuby is a Ruby subset and an ahead-of-time compiler for microcontrollers. It
translates Ruby to C++ in a "better C" style, which a standard ARM toolchain plus the
target platform SDK or HAL turns into a native firmware image. There is no VM and no
garbage collector; every type is resolved at compile time.

**This repository is a throwaway feasibility prototype, not that compiler.** It exists to
answer one question by running it: can the pipeline the design calls for actually be
built end to end? It has no tests, no diagnostics and no error handling, and the only
command-line options are the few the build itself cannot do without. Happy path only, and
it is meant to be thrown away once it has answered the question.

The language specification and the real implementation live in separate repositories
that are not public yet. Nothing here points at them. Comments record why a decision was
made in their own terms, so this repository reads on its own.

Covered so far:

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
- **The STM32Cube binding** — a user-owned NUCLEO-F446RE CubeMX project outside this
  repository owns clock, pin, startup, HAL initialization and link configuration. Pass
  12 adds HAL-backed GPIO, timing, LD2, USART2 and I2C1 translation units, entered from a
  CubeMX-preserved user section after every peripheral is initialized. `bareruby build`
  generates one application, synchronizes only the reached units, and drives
  STM32CubeIDE's headless builder. A physical board has been programmed over SWD, with
  LD2 and USART2 exercised; I2C links against STM32CubeF4 HAL 1.28.3 but remains
  hardware-unverified.

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
  [README](target/api/arduino/README.md): PWM has a duty and no frequency, because
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
  CubeMX project. Nor is it a fact about the API alone, because a Pico and a Pico W differ
  under the very same SDK — one has its LED on a pin and the other behind a radio. It is a
  fact about the two together, so it lives where the two meet:

  ```ruby
  # target/api/pico_sdk/machine/pico_w.rb
  module PicoSdkBinding
    module PicoW
      def self.onboard_led_file = ONBOARD_LED_RADIO_FILE

      def self.onboard_led_text = ONBOARD_LED_RADIO

      def self.onboard_led_libraries = [RADIO_LIBRARY]
    end

    MACHINES[:pico_w] = PicoW
  end
  ```

  A board answers for itself, by naming what the API beside it already carries. Nothing is
  worked out: `binding.rb` holds the C++ and the names, exactly as it does for GPIO and
  UART, and there is no branch in it that decides which board gets which. A board an API
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

Every object is a reference, which is what Ruby does (`samples/object.rb`). `b = a` names
the object `a` names rather than a copy of it, a method is handed the caller's object and
not a copy — so what it changes, the caller sees — and a method that returns an object
returns that object. Only `dup` duplicates one. Storage belongs to the binding the
creation expression was assigned to: a local holds the instance on the stack, an instance
variable holds it inside the owning struct, and every other binding of that type is a
pointer to it. The array and the arena reached that rule first, one milestone at a time;
it holds for every object, peripherals included. The variable-length string is the one
whose storage no binding owns — the region owns it, handle and bytes both, which is what
lets a method create one and hand it back — and the rule that every binding names the same
string is unchanged by that.

`asleep` is the one call here that neither PicoRuby nor the mruby/c Common I/O guideline
defines. `sleep` and `sleep_ms` wait from the moment they are called — that is what
mruby/c and pico-sdk both do underneath — so a loop's period is its body plus the wait,
and it drifts by whatever the body costs. `asleep`, `asleep_ms` and `asleep_us` wait from
the moment the previous one returned instead, so the body comes out of the wait and the
loop holds its period. All three share one mark, counted in microseconds since boot; it
starts at boot and moves to each return. A turn that overruns does not catch up: it
returns at once and the missed time is gone. Holding the phase across an overrun, and
keeping more than one mark, are left out on purpose — a single mark serves one call per
loop, which is what these programs need. The name is provisional, and the leading `a`
means nothing at all.

The programs these milestones were verified with are in [`samples/`](samples/README.md),
which lists what each one covers and records what the two ported programs had to change.
`ref.rb`, the representative program from the design documents, stays here at the root
because it is what `bareruby compile` compiles when it is given no argument.

## The short way

`bareruby` is the only command. Its verbs stack: `build` compiles first, `deploy` builds
first, so each does its own work and then the next one's.

```sh
cd bareruby-prototype
./bareruby target add                        # once per board: answer a few questions
./bareruby deploy app.rb                     # compile, build, and write it onto them
./bareruby build app.rb --target=pico2       # one target, no flashing
./bareruby flash                             # write what the last build left, again
./bareruby compile app.rb                    # first stage only, no toolchain needed
./bareruby                                   # prints usage
```

| Verb | What it does | Reads `target.yml` |
| --- | --- | --- |
| `compile` | Ruby to C++, into `build/<composition>/` | no — without `--target` the target is the machine doing the compiling |
| `build` | `compile`, then each API's toolchain, leaving the artifact beside its sources | yes |
| `flash` | writes what `build` left onto the boards that take it | yes |
| `deploy` | `build`, then `flash` | yes |
| `target add` | asks which board this is and writes it into `target.yml` | writes it |
| `target list` | every board that can be targeted, by family | no |

`build` defaults `PICO_SDK_PATH` and `PICO_TOOLCHAIN_PATH` to the locations used below and
takes them from the environment when they are already set. Toolchain output is shown only
when a step fails.

The rest of this file is what `bareruby` does, step by step, and how to install what it
needs.

### Saying which boards are here

`target.yml` is not tracked, because which boards are attached is true of a desk rather
than of the project. It is not meant to be written by hand either — `./bareruby target
add` asks, and writes the answer:

```
Which board is it?
  1) Raspberry Pi Pico, through pico-sdk
  2) ST NUCLEO, through STM32Cube and CubeIDE
  3) This machine, with every peripheral traced instead of driven
1-3> 1

Which one?
  1) raspberry-pi-pico
  2) raspberry-pi-pico-w
  …
```

and what it writes is an entry:

```yaml
bareruby:
  targets:
    - machine: pico
      api: pico_sdk
      triple: thumbv6m-none-eabi
      debug: true
      boards:
        - E6625888179C592E
```

An entry always spells out all three parts of a composition, because none of them settles
another. One board is reachable through more than one API — a NUCLEO board through
STM32Cube or through STM32duino — and one board whose chip carries two instruction sets is
built for either of them, as an RP2350 is for Arm or for RISC-V. `boards:` is a list
because several identical boards take the same one artifact.

None of that is anything to look up, which is why it is asked for instead. What is asked,
in what order, and what else a family needs — the path to a CubeIDE project, the serial of
an ST-LINK probe — is in [`target-catalog.yml`](target-catalog.yml) rather than in the
command, so a board that does not exist yet is reached by adding to that file. It restates
no composition: a family names targets, and their machine, API and triple come from
`target/target.rb`, where they already are. `./bareruby target list` prints them all, and
an entry that names nothing prints them too.

[`target.yml.sample`](target.yml.sample) documents every field, for reading a file back
once it exists.

## Running the first stage

```sh
./bareruby compile                       # defaults to ref.rb
./bareruby compile samples/blink.rb
./bareruby compile -d samples/blink.rb   # debug firmware
```

### Choosing targets

A target is a machine the artifacts are produced for. There are seven:

| Target | Short | Machine | Chip |
| --- | --- | --- | --- |
| `host` | — | the machine doing the compiling | — |
| `raspberry-pi-pico` | `pico` | Raspberry Pi Pico | RP2040 |
| `raspberry-pi-pico-w` | `picow` | Raspberry Pi Pico W | RP2040 |
| `raspberry-pi-pico2` | `pico2` | Raspberry Pi Pico 2 | RP2350 |
| `raspberry-pi-pico2-w` | `pico2w` | Raspberry Pi Pico 2 W | RP2350 |
| `stm32-nucleo-f446re` | `f446` | NUCLEO-F446RE | STM32F446RE |
| `arduino-mega2560` | `mega` | Arduino Mega 2560 | ATmega2560 |

The short names are for typing at a prompt; the full name is what the `build/` directory
and the manifest are named after either way, so nothing downstream has two spellings to
know about.

`--target=` names one and is repeatable, so a single run produces artifacts for as many
machines as it lists:

```sh
./bareruby compile --target=host samples/blink.rb
./bareruby compile --target=raspberry-pi-pico --target=raspberry-pi-pico2 samples/blink.rb
./bareruby compile --target=pico --target=picow --target=pico2 --target=pico2w samples/heartbeat.rb
./bareruby compile --target=f446 --no-exceptions samples/heartbeat.rb
```

`bareruby compile` reads no configuration at all: a compilation is exactly what its
command line asked for, and with nothing said the target is `host`. From `build` onwards a
command needs to know which desk it is standing at, and that is what `target.yml` answers.

### Where the artifacts land

A target's directory is the composition that made it:

```
build/none-host-x86_64-pc-linux/
build/pico-pico_sdk-thumbv6m-none-eabi/
build/pico_w-pico_sdk-thumbv6m-none-eabi/
build/pico2-pico_sdk-thumbv8m.main-none-eabihf/
build/pico2_w-pico_sdk-thumbv8m.main-none-eabihf/
build/nucleo_f446re-stm32cube-thumbv7em-none-eabihf/
build/mega2560-arduino-avr-none/
```

It is `<machine>-<api>-<triple>`, and it is long because that is how much it takes to be
unique. The triple alone will not do: a Pico and a Pico W are both `thumbv6m-none-eabi` and
their firmware is not the same — one drives its LED from a pin and the other through the
radio, which brings a driver and a firmware blob with it. The board alone will not do
either, because an RP2350 is built for Arm or for RISC-V. What lies underneath is left out
of the name only because the triple already carries it. An entry in `target.yml` that gives
a `name:` uses that instead, which is how one composition can be built twice — a debug one
and a release one — without the two landing in one place.

Only the selected targets are written. Their directories hold the generated entry point
and a `manifest.txt`; Pico targets also receive a `CMakeLists.txt`, the STM32 target
receives the exact source list synchronized into its existing CubeIDE project, and the
Mega receives a sketch directory the reached translation units are gathered into. The runtime
and the bindings sit above them in `build/` and are shared. The Pico boards use the same
pico-sdk binding — the peripherals are reached through the SDK, which spells them the same
way whichever chip is underneath — and differ only in the two words their `CMakeLists.txt`
hands to it.

Those two words are pico-sdk's, not the boards'. `PICO_BOARD` is what that SDK calls a
board, and `PICO_PLATFORM` is not even the chip's name: an RP2350 answers to
`rp2350-arm-s` or `rp2350-riscv` once which of its two instruction sets to build for is
chosen. So they are kept where the board and the API meet rather than on the board:

```ruby
# target/api/pico_sdk/machine/pico2_w.rb
def self.pico_board = "pico2_w"

def self.pico_platform = "rp2350"
```

What is left on the board itself is what is true of it whoever asks — the key it is known
by, and the chip it carries.

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

`-d` / `--debug` only affects the freestanding target. It turns on USB stdio, so
`puts` reaches a USB serial port instead of being dropped, and — the reason it exists —
the board **stays enumerated as a USB device while the program runs**, which is what
lets `flash.sh` reflash it without the BOOTSEL button. It costs code size:

| | default | `--debug` |
| --- | --- | --- |
| `.uf2` | 23040 B | 53248 B |
| `text` (flash) | 15536 B | 30596 B |
| `bss` (RAM) | 1484 B | 3604 B |

It needs the SDK's TinyUSB submodule. Without it the SDK builds a firmware identical to
the default one and says so only in a warning, so `--debug` looks like it worked and the
board never enumerates.

Only Ruby is needed for this (Prism ships with Ruby 4.0). Every run rewrites two
directories, neither of which is tracked in git — they are outputs, and they changed on
every commit while they were:

- `dump/` — one binary snapshot (`.bin`) and one inspector text dump (`.txt`) per
  pass boundary. The pipeline reloads each representation from its own binary dump
  before handing it to the next pass, so resumability and byte-level determinism are
  exercised on every run.
- `build/` — the first-stage artifacts: the peripheral binding (declaration plus one
  implementation per kind of machine), the runtime, and one directory per selected
  target holding `main.cpp`, the build manifest and, for a board, `CMakeLists.txt`.
  **`build/` is deleted and regenerated on every run.**

### Where the shipped C++ comes from

Most of the C++ that lands in `build/` is carried by this repository rather than written
line by line by the compiler, and where a piece of it lives says who it belongs to.

What is the same everywhere belongs to the last pass and sits beside it in
`pass/pass_12_cpp_source_generator/`: the runtime proper — the arena, the strings, the
fixed-point arithmetic — and the declarations every binding answers.

What differs by the API being called sits under `target/api/<api>/`, one directory each:
`binding.rb` implements those declarations in that API's own words, `build.rb` writes down
what the second stage is, `toolchain.rb` runs it, and `flash.rb` puts the result on a
machine. Those four are everything an API owns, and they are the only files that change
when a new one is added. Each names its own translation units, because the name a piece of
C++ is written under belongs with that C++ and nowhere else.

`main.cpp`, the one C++ file that is written rather than carried, is rendered from the
low-level IR; the API it is built for supplies the entry point and says whether output has
anywhere to go — and for a machine whose `main` is owned by someone else, the file is
called `bareruby_program.cpp` instead, because this side does not name an entry point it
does not own.

What is left of the pass is the assembly: it asks the low-level IR what the program
reaches for, asks each source for its files, and hands each target the ones it needs. All
of it was one file until the C++ grew to two thirds of it, which is a poor place to read
any of it from.

## Second stage: STM32CubeIDE

The NUCLEO-F446RE target uses a user-owned CubeMX/CubeIDE project outside this
repository. CubeMX owns clocks, pins, HAL initialization, startup and linker scripts;
pass 12 supplies C++ through the HAL. The complete generation, synchronization, and
headless build is one command:

Where that project lives is something only this desk knows, so it is said in `target.yml`
rather than on the command line:

```yaml
    - machine: nucleo_f446re
      api: stm32cube
      triple: thumbv7em-none-eabihf
      options:
        cube_project: /path/to/F446_Sample
        configuration: Debug
```

```sh
./bareruby build samples/heartbeat.rb --target=f446 --no-exceptions
```

The toolchain finds `headless-build.sh` or `stm32cubeide` in `PATH` and under the normal
`/opt/st` installation tree; `STM32CUBEIDE=/path/to/headless-build.sh` overrides that. It
copies in only the translation units this program reached for, replaces nothing but the
files it owns, and brings the linked ELF back to `build/<composition>/bareruby_program.elf`
so that flashing needs to know nothing about where the external project keeps its output.
The binding's [README](target/api/stm32cube/README.md) records project preparation, the
ownership boundary, CubeMX regeneration, pin mapping, and supported bindings.

`./bareruby flash --target=f446` writes that ELF over SWD with `STM32_Programmer_CLI`,
naming ST-LINK probe serials from `boards:` when more than one probe is attached. **That
path has never been run** — the STM32 firmware verified so far was flashed by hand.

## Second stage: arduino-cli

The Mega 2560 is built by `arduino-cli`, which reads a sketch — a directory holding a
file of its own name, compiled whole. So the target's directory holds a
`bareruby_program/` the toolchain gathers into: the translation units the manifest names,
and the two headers, copied in beside a `bareruby_program.ino` that has nothing in it
because the program is in the `.cpp` next to it. The whole of it is one command:

```sh
./bareruby build samples/heartbeat.rb --target=mega --no-exceptions
```

`--no-exceptions` is not optional here. The core compiles with `-fno-exceptions` and this
libc carries no unwinder, so a program containing `begin` has no build for this board
either way round: with the flag the first stage rejects it, and without the flag the
second stage does.

Two things are needed, neither of them needing `sudo`.

```sh
mkdir -p ~/toolchains/arduino-cli && cd ~/toolchains/arduino-cli
curl -fsSLO https://downloads.arduino.cc/arduino-cli/arduino-cli_latest_Linux_64bit.tar.gz
tar xf arduino-cli_latest_Linux_64bit.tar.gz
./arduino-cli core install arduino:avr
```

That is 37 MB for the command and 44 MB for the core, which brings avr-gcc, avr-libc and
avrdude with it. `~/toolchains/arduino-cli` is where `bareruby` looks when the command is
not already on `PATH`; the core lands in `~/.arduino15` wherever it came from.

What comes back is `bareruby_program.hex` and `bareruby_program.elf`, beside the sources
they were made from rather than under whatever name the tool gave them.

```sh
./bareruby flash --target=mega
```

writes the `.hex` over the same serial port the board talks on. There is no image to read
the chip out of and no volume to copy onto, so what identifies a board here is the port —
and rather than guess at one, `arduino-cli` is asked which ports carry the board this
firmware was built for. Three USB serial devices are attached to the desk this was
written on, two of them Picos; the right one is found and the other two are never
candidates. `boards:` in `target.yml` names a port only when two of the same board are
attached.

The board resets when the port is opened, so a serial reader sees the program from its
first line:

```sh
stty -F /dev/ttyACM2 115200 raw -echo
timeout 6 cat /dev/ttyACM2
```

There is no `--debug` here and nothing to turn on for output. The console is a bridge
chip of the board's own, always attached and always listening, so `puts` reaches it in
every build — where on a Pico stdout costs a USB stack and is off unless it is asked for.

## Second stage: hosted

Needs a GNU `g++` (version 12 or newer). Ubuntu 24.04 ships 13.3, which is fine.
The build command is recorded in the manifest, so just run what it says:

```sh
cd build/none-host-x86_64-pc-linux
g++ -std=gnu++20 -fno-rtti -I.. -o bareruby_program \
    main.cpp ../bareruby_binding_host.cpp ../bareruby_runtime_fixed.cpp \
    ../bareruby_runtime_stdio.cpp
./bareruby_program            # fd1 = puts, fd2 = peripheral call trace
```

The runtime is split across translation units by what each part costs to link, so the
source list varies with the program. Take it from `manifest.txt` rather than from here.

For `samples/uart_receive.rb`, stdin is the hosted UART wire:

```sh
printf 'ABCDhello UART\n' | ./bareruby_program
```

For `samples/i2c.rb`, stdin supplies the bytes returned by the hosted read:

```sh
printf 'OK' | ./bareruby_program
```

`samples/blink.rb` loops forever by design; use `timeout 1 ./bareruby_program` to look at
the head of the trace.

## Second stage: freestanding (`.uf2`)

Three tools are required. None of them need `sudo`.

### 1. pico-sdk

Use **2.3.0** for both boards. RP2350 support arrived in SDK 2.0.0 — 1.5.1 stops at
`rp2350.cmake does not exist` — and RP2040 is still supported there, so one checkout
serves both.

```sh
mkdir -p ~/pico
git clone -b 2.3.0 --depth 1 https://github.com/raspberrypi/pico-sdk.git ~/pico/pico-sdk-2
git -C ~/pico/pico-sdk-2 submodule update --init --depth 1 lib/tinyusb lib/cyw43-driver
```

That is 33 MB for the SDK, 25 MB for TinyUSB and 10 MB for the CYW43 driver.
**The CYW43 driver is what a wireless board's on-board LED needs** — that LED hangs off
the radio, and the driver carries the firmware the radio runs. Without the submodule a
`raspberry-pi-pico-w` or `raspberry-pi-pico2-w` build that uses `OnboardLED` fails in
cmake; nothing else needs it.

**TinyUSB is what `--debug` needs**: it
turns on USB stdio, and without the submodule the SDK prints "TinyUSB submodule has not
been initialized; USB support will be unavailable" and builds a firmware byte-identical
to the non-debug one. Default builds disable both stdio channels and do not need it, so
the warning is harmless there — but a `--debug` build that silently is not one is worse
than a missing dependency, hence initializing it up front.

`picotool` needs no separate install: SDK 2.x downloads and builds it on demand. Left
alone it lands inside the target's build tree, which the next first-stage run deletes, so
`PICOTOOL_FETCH_FROM_GIT_PATH` points it somewhere outside — `bareruby` defaults that to
`~/pico/picotool` (17 MB, built once). Its libusb-dependent parts are skipped when the
headers are absent, which costs nothing here: only `.uf2` generation is wanted.

Earlier work in this repository used **1.5.1**, which generates the `.uf2` with the
`elf2uf2` bundled in the SDK and so needs no picotool. That was the only reason to stay
on it, and it stopped being a reason once picotool was installed for the Pico 2. What
moving cost is recorded below.

### 2. ARM GNU toolchain

Download ARM's official release and unpack it. It bundles newlib, which is what
pico-sdk needs.

```sh
mkdir -p ~/toolchains && cd ~/toolchains
curl -fsSLO https://developer.arm.com/-/media/Files/downloads/gnu/13.2.rel1/binrel/arm-gnu-toolchain-13.2.rel1-x86_64-arm-none-eabi.tar.xz
tar xf arm-gnu-toolchain-13.2.rel1-x86_64-arm-none-eabi.tar.xz
```

Note the extracted directory capitalises the release differently from the tarball:
`arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi`.

**Two Homebrew routes that do not work on Linux**, both verified here:

- `brew install arm-none-eabi-gcc` installs a bare cross compiler **without newlib**.
  There is no `libc.a` and no `nosys.specs`, and the pico-sdk build dies while linking
  `boot_stage2` with `cannot read spec file 'nosys.specs'`. There is no newlib formula
  in homebrew-core to pair with it.
- `brew install --cask gcc-arm-embedded` fails with `This cask requires macOS`. Casks
  are macOS-only; Linuxbrew cannot install them. The cask would have fetched exactly
  the ARM release downloaded above.

### 3. cmake

```sh
brew install cmake
```

Any recent cmake works; 4.4.0 was used here. The generated `CMakeLists.txt` declares
`cmake_minimum_required(VERSION 3.13)`, which cmake 4.x still accepts.

### Building the firmware

```sh
cd build/pico-pico_sdk-thumbv6m-none-eabi
export PICO_SDK_PATH=$HOME/pico/pico-sdk-2
export PICO_TOOLCHAIN_PATH=$HOME/toolchains/arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi
cmake -B build -S .
cmake --build build
```

The result is `build/bareruby_program.uf2`. The `build/pico-pico_sdk-thumbv6m-none-eabi/build/` tree is
gitignored; `bareruby` deletes it on the next run along with the rest of `build/`.
`build/pico2-pico_sdk-thumbv8m.main-none-eabihf` is built by exactly the same commands with the same SDK — the
board's `CMakeLists.txt` carries the whole of the difference.

Output for `samples/blink.rb`, measured on both boards from the same first stage:

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

## Flashing a Pico from WSL

Windows owns the USB device until it is handed to WSL, so a Pico in BOOTSEL mode does
not appear here on its own. Attach it first, from an elevated Windows shell:

```powershell
usbipd list                    # find the bus id of "RP2 Boot"
usbipd bind   --busid <BUSID>  # once per device
usbipd attach --busid <BUSID> --wsl
```

The bootloader then shows up as a USB mass storage device — `2e8a:0003 Raspberry Pi
RP2 Boot` in `lsusb`, a removable 128 MiB disk in `dmesg`. Then run:

```sh
target/api/pico_sdk/flash.sh --list                # what is attached, and the fstab line for each
target/api/pico_sdk/flash.sh                       # defaults to the raspberry-pi-pico artifact
target/api/pico_sdk/flash.sh path/to/other.uf2
target/api/pico_sdk/flash.sh --board SERIAL path/to/other.uf2
```

The script locates boards by SCSI vendor `RPI` and by USB vendor `2e8a` rather than by a
fixed path, refuses to write unless the mounted volume carries the bootloader's
`INFO_UF2.TXT`, and treats the device disappearing as the success signal — the board
resets the moment the last block lands, so the copy, the sync and the unmount are all
expected to fail at the end.

### Several boards at once

Boards can stay attached together, which is what makes a Pico and a Pico 2 usable as one
test bench. **Which board a firmware goes to follows from the firmware**: bytes 28..31 of
a `.uf2` are the family id of the chip it was built for (`0xE48BFF56` for RP2040,
`0xE48BFF57` for RP2350), and only boards carrying that chip are considered. `deploy` uses
that to write every board a run selected, one after another:

```sh
./bareruby deploy samples/blink.rb          # every entry in target.yml
```

Two boards of the *same* chip — a Pico and a Pico W, a Pico 2 and a Pico 2 W — cannot be
told apart that way. That is not an oversight in the script; it is the same fact a
composition names a machine as well as a triple for. `boards:` in `target.yml` says which
one, and given nothing to go on `flash.sh` refuses to guess and prints the candidates:

```
flash: 2 boards carry rp2040, so the image does not say which one to use.
         --board E6625888179C592E   (running, /dev/ttyACM1)
         --board E0C9125B0D9B       (bootsel, /dev/sdf1)
```

`--list` shows the serials. One caveat found the hard way: **an RP2040 reports a
different serial in BOOTSEL than while running** — the bootrom's id (12 hex digits)
against the flash id pico-sdk reads (16 hex digits). They are both stable per board, but
they are different numbers, so a board cannot be followed across a reset by its serial.
An RP2350 happens to report the same number in both modes; do not rely on that. What
`flash.sh` follows across the reset instead is arrival: the board that is in BOOTSEL and
was not a moment earlier is the one it just reset.

### Reflashing without the BOOTSEL button

A firmware built with `-d` keeps its USB CDC interface up, and pico-sdk reboots the
board into BOOTSEL when that port is opened at 1200 baud. `flash.sh` does this itself:
if no bootloader volume is present it looks for a `/dev/ttyACM*`, resets it, waits for
the board to come back as mass storage, and flashes. Edit, rebuild, rerun `flash.sh` —
no button, no replugging.

usbipd sees BOOTSEL and the running program as two different devices, so **bind both of
them once**, and keep an auto-attach running so the flip between them is picked up:

```powershell
usbipd bind   --busid <BUSID>               # once while in BOOTSEL
usbipd bind   --busid <BUSID>               # once more while the program runs
usbipd attach --busid <BUSID> --wsl --auto-attach
```

The ids differ per chip: an RP2040 is `2e8a:0003` in BOOTSEL and `2e8a:000a` running, an
RP2350 `2e8a:000f` and `2e8a:0009`. **The auto-attach is not optional for a bench that
stays plugged in.** Without it every reset drops the board out of WSL and the next flash
stops at "no board came back in BOOTSEL mode" — which is a WSL plumbing failure, not a
board failure. One auto-attach per board.

### Mounting without sudo

Only the mount needs privileges. One line in `/etc/fstab` per board removes even that:

```
/dev/disk/by-id/usb-RPI_RP2_E0C9125B0D9B-0:0-part1    /mnt/pico  vfat noauto,user,umask=000 0 0
/dev/disk/by-id/usb-RPI_RP2350_34319CF054AB3BD6-0:0-part1 /mnt/pico2 vfat noauto,user,umask=000 0 0
```

`target/api/pico_sdk/flash.sh --list` prints these lines for whatever is in BOOTSEL, serial and all. The
mount points are read back out of `/etc/fstab`, so they can be named anything as long as
each is distinct.

Naming boards by label instead — `/dev/disk/by-label/RPI-RP2`, `/dev/disk/by-label/RP2350`
— also works and is shorter, but only while one board of each chip is attached: two Pico 2
boards both label their volume `RP2350` and the link points at whichever udev saw last.
The `by-id` path carries the serial and stays unambiguous.

The `user` option lets any user mount that one entry, and nothing else — much narrower
than a `NOPASSWD` sudoers rule. `/dev/ttyACM*` is already reachable through the `dialout`
group, so with these entries `flash.sh` needs no root at all. Without a line for the
attached board, the script falls back to re-executing itself under `sudo` and prints the
line that would have avoided it.

Two traps worth knowing:

- The mount must be the **setuid** system binary. If another `mount` comes first on
  `PATH` (Homebrew's util-linux, for instance) it is not setuid and refuses with
  `must be superuser to use mount`. The script calls `/usr/bin/mount` explicitly.
- udev publishes `/dev/disk/by-label/RPI-RP2` slightly after the block device appears,
  so a mount issued immediately after a reset can lose the race. The script retries.

Verified end to end on a Raspberry Pi Pico. With a default build, `2e8a:0003`
disappears from `lsusb` after flashing and GP25 (the on-board LED) blinks at the
500 ms period written in `samples/blink.rb`; the board presents no USB interface at all,
which is correct with both stdio channels disabled, and the button is needed to flash
again. With `-d` it comes back as `2e8a:000a` with a `/dev/ttyACM0`, and successive
edits were flashed by rerunning `bareruby flash` alone — verified by changing the blink
period to 100 ms and then 800 ms and watching the LED follow.

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

## Versions this was verified against

| Tool | Version |
| --- | --- |
| Ruby | 4.0.3 |
| GNU g++ (hosted) | 13.3.0 |
| pico-sdk | 2.3.0 (both boards) |
| arm-none-eabi-g++ | 13.2.Rel1 (ARM official release) |
| cmake | 4.4.0 |
| arduino-cli | 1.5.2-rc.1 |
| arduino:avr core | 1.8.8 |
| avr-g++ | 7.3.0 (atmel3.6.1-arduino7) |
| STM32CubeIDE | 2.2.0 |
| GNU Tools for STM32 | 14.3.1 |
| STM32CubeMX project | 6.15.0, STM32CubeF4 HAL 1.28.3 |
| STM32CubeProgrammer | 2.23.0 |

The STM32 translation units and complete ELF were built with STM32CubeIDE's GNU Tools
for STM32 14.3.1. Headless build, SWD programming, LD2, and USART2 were verified on a
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
