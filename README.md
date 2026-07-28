# bareruby-prototype

BareRuby is a Ruby subset and an ahead-of-time compiler for microcontrollers. It
translates Ruby to C++ in a "better C" style, which a standard toolchain
(`arm-none-eabi-g++` with pico-sdk) turns into a native firmware image. There is no
VM and no garbage collector; every type is resolved at compile time.

**This repository is a throwaway feasibility prototype, not that compiler.** It exists to
answer one question by running it: can the pipeline the design calls for actually be
built end to end? It has no tests, no diagnostics, no error handling and no CLI options.
Happy path only, and it is meant to be thrown away once it has answered the question.

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
  converter channel is rejected while compiling. No new pass.
- **M2.7** — fixed-capacity arrays (`samples/array.rb`): `Array.new(n[, init])`, array
  literals, `[]`, `[]=`, `size` and `dup`. Single element type, capacity settled while
  compiling. Assignment shares the array as Ruby does, and only `dup` duplicates it;
  indexing is pointer arithmetic and is not range checked. No new pass.
- **M3 — the arena**, the third layer of the memory model (`samples/arena.rb`):
  `arena(size:) { |a| … }` blocks, nested, `Arena.new(size:)` with `reset` for the
  long-lived form, and `a.array(n)`, an array whose length is a run-time value — the
  case the first two layers cannot serve. Allocation bumps one pointer, running out
  panics rather than growing, and each region is a static buffer belonging to the site
  that declared it: asking for 1024 bytes more moves `bss` by exactly 1024. Release is
  that pointer going back, done by a guard whose destructor runs on the way out of the
  scope, so an exception leaving the block releases the region as well. An arena is
  handed to the code doing the work, as the design writes it, and travels by reference:
  what it hands out is recorded in the arena, so a copy would let two callers hand out
  the same room. An allocation may not be stored in an instance variable or in a local
  the block did not introduce. No new pass.
- **M3 — the variable-length string** (`samples/string.rb`), the other value the first two
  layers cannot hold: `a.string`, `a.string("text")`, `a.string(other_string)` and
  `a.string("count: #{n}")` create one, and it answers `<<`, `+`, `size`, `length`, `dup`,
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
  assigned on every path through `initialize` starts in that same state. The sample
  exercises both `Int32?` and a variable-length
  string pointer in the same representation scheme. This feasibility slice follows the
  local-only withdrawal line: instance-variable narrowing and invalidation are not
  implemented. No new pass.

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
because it is what `compile.rb` compiles when it is given no argument.

## The short way

`brd` runs the whole cycle — first stage, second stage, flash — for one program:

```sh
cd bareruby-prototype
./brd app.rb -d      # debug firmware: USB stays up, reflashable without the button
./brd app.rb         # default firmware
./brd                # prints usage
```

It defaults `PICO_SDK_PATH` and `PICO_TOOLCHAIN_PATH` to the locations used below and
takes them from the environment when they are already set. cmake output is shown only
when a step fails.

The rest of this file is what `brd` does, step by step, and how to install what it
needs.

## Running the first stage

```sh
ruby compile.rb                       # defaults to ref.rb
ruby compile.rb samples/blink.rb
ruby compile.rb -d samples/blink.rb   # debug firmware
```

`--no-exceptions` drops the exception mechanism: `begin` becomes a compile error and
the unwinder and its tables are left out. On an rp2040 build of `samples/blink.rb` that is
13220 B of text against 8668 B, so the mechanism costs about 4.5 KB of flash and 316 B
of RAM even in a program that never raises.

A program that actually raises pays far more. `bareruby_throw` pulls in the C++ ABI, and
with it the terminate handler's name demangler and malloc: `samples/m25.rb` comes to 73848 B
of text. That is why the throw lives in its own translation unit and is linked only into
programs that reach it — `--gc-sections` cannot remove it once it is compiled in.

An arena is the other thing here that is worth what it costs rather than free. The same
six statements written twice — once against `Array.new(3, 0)`, once against `a.array(3)`
inside an arena block — come to 8364 B of text with the fixed-capacity array and 37036 B
with the arena, both under `--no-exceptions`. The 28 KB between them is the panic path:
exhaustion calls `bareruby_panic`, and `fprintf` plus `exit` bring stdio with them. With
exceptions enabled the same pair is 12884 B and 90604 B, and the further 50 KB is the
guard — a scope holding an object with a destructor gives its function a cleanup landing
pad, which references `__gxx_personality_v0` and drags in the same C++ ABI a `raise`
does. Releasing the region when an exception leaves the block is what that buys.

A variable-length string adds almost nothing to what the region already costs: six
statements that create one, append to it twice and print it come to 37244 B of text under
`--no-exceptions`, against the 37036 B the arena array's six cost above. The allocator and
its panic path are what both are paying for. The interpolation form is the part worth
counting — `a.string("readings: #{count}")` makes `vsnprintf` reachable and takes the same
program to 43908 B, where that interpolation assigned to a fixed-capacity local costs
17784 B and no region at all. `samples/string.rb`, which uses every form, is 44572 B of
text and 3336 B of `bss`, 1792 of which is the three regions it declares.

`samples/uart_receive.rb` is 37916 B of text and 1804 B of `bss` under
`--no-exceptions`; its region accounts for 256 B of the latter. The receive path therefore
fits beside the arena and string runtime without introducing another large dependency.

`samples/i2c.rb` is 38508 B of text and 1800 B of `bss` under `--no-exceptions`, and its
`.uf2` is 77312 B. That includes mixed-output flattening, a write, and a register-select
write followed by a repeated-start read.

`samples/nilable.rb` is 37116 B of text and 1672 B of `bss` under `--no-exceptions`;
its `.uf2` is 74240 B. The sample includes the arena and variable-length string runtime,
so the tagged representation and its control flow fit within the cost already established
for those M3 facilities.

`-d` / `--debug` only affects the freestanding target. It turns on USB stdio, so
`puts` reaches a USB serial port instead of being dropped, and — the reason it exists —
the board **stays enumerated as a USB device while the program runs**, which is what
lets `flash.sh` reflash it without the BOOTSEL button. It costs code size:

| | default | `--debug` |
| --- | --- | --- |
| `.uf2` | 17408 B | 45056 B |
| `text` (flash) | 8604 B | 22460 B |
| `bss` (RAM) | 1160 B | 3652 B |

Only Ruby is needed for this (Prism ships with Ruby 4.0). Every run rewrites two
directories, neither of which is tracked in git — they are outputs, and they changed on
every commit while they were:

- `dump/` — one binary snapshot (`.bin`) and one inspector text dump (`.txt`) per
  pass boundary. The pipeline reloads each representation from its own binary dump
  before handing it to the next pass, so resumability and byte-level determinism are
  exercised on every run.
- `build/` — the first-stage artifacts: the peripheral binding (declaration plus one
  implementation per target), the hosted runtime, and per-target `main.cpp`, build
  manifest and `CMakeLists.txt`. **`build/` is deleted and regenerated on every run.**

## Second stage: hosted

Needs a GNU `g++` (version 12 or newer). Ubuntu 24.04 ships 13.3, which is fine.
The build command is recorded in the manifest, so just run what it says:

```sh
cd build/hosted
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

## Second stage: freestanding (rp2040, `.uf2`)

Three tools are required. None of them need `sudo`.

### 1. pico-sdk

Use **1.5.1**. That release generates the `.uf2` with the `elf2uf2` bundled in the SDK.
SDK 2.x moved `.uf2` generation out to `picotool`, which then has to be installed
separately — avoid that for now.

```sh
mkdir -p ~/pico
git clone -b 1.5.1 --depth 1 https://github.com/raspberrypi/pico-sdk.git ~/pico/pico-sdk
```

The TinyUSB submodule is not needed: both stdio channels are disabled in the generated
`CMakeLists.txt`, so the "TinyUSB submodule has not been initialized" warning during
configuration is expected and harmless.

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
cd build/rp2040
export PICO_SDK_PATH=$HOME/pico/pico-sdk
export PICO_TOOLCHAIN_PATH=$HOME/toolchains/arm-gnu-toolchain-13.2.Rel1-x86_64-arm-none-eabi
cmake -B build -S .
cmake --build build
```

The result is `build/bareruby_program.uf2`. The `build/rp2040/build/` tree is gitignored;
`compile.rb` deletes it on the next run along with the rest of `build/`.

Verified output for `samples/blink.rb`:

| Property | Value |
| --- | --- |
| `.uf2` size | 17408 bytes, 34 blocks |
| UF2 family id | `0xE48BFF56` (RP2040) |
| UF2 target address | `0x10000000` (XIP flash base) |
| `text` / `data` / `bss` | 8604 B / 0 B / 1160 B |

`arm-none-eabi-objdump -d bareruby_program.elf` shows the blink loop as Cortex-M0+
instructions, with `bareruby_main` inlined into `main` by the release build.

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
./flash.sh                       # defaults to the rp2040 artifact
./flash.sh path/to/other.uf2
```

The script locates the device by SCSI vendor `RPI` and model `RP2` rather than by a
fixed path, refuses to write unless the mounted volume carries the bootloader's
`INFO_UF2.TXT`, and treats the device disappearing as the success signal — the RP2040
resets the moment the last block lands, so the copy, the sync and the unmount are all
expected to fail at the end.

### Reflashing without the BOOTSEL button

A firmware built with `-d` keeps its USB CDC interface up, and pico-sdk reboots the
board into BOOTSEL when that port is opened at 1200 baud. `flash.sh` does this itself:
if no bootloader volume is present it looks for a `/dev/ttyACM*`, resets it, waits for
the board to come back as mass storage, and flashes. Edit, rebuild, rerun `flash.sh` —
no button, no replugging.

usbipd sees BOOTSEL (`2e8a:0003`) and the running program (`2e8a:000a`) as two
different devices, so **bind both of them once**, and keep an auto-attach running so
the flip between them is picked up:

```powershell
usbipd bind   --busid <BUSID>               # once while in BOOTSEL
usbipd bind   --busid <BUSID>               # once more while the program runs
usbipd attach --busid <BUSID> --wsl --auto-attach
```

### Mounting without sudo

Only the mount needs privileges. One line in `/etc/fstab` removes even that:

```
/dev/disk/by-label/RPI-RP2 /mnt/pico vfat noauto,user,umask=000 0 0
```

The `user` option lets any user mount that one entry, and nothing else — much narrower
than a `NOPASSWD` sudoers rule. `/dev/ttyACM*` is already reachable through the
`dialout` group, so with this entry `flash.sh` needs no root at all. Without it, the
script falls back to re-executing itself under `sudo`.

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
edits were flashed by rerunning `flash.sh` alone — verified by changing the blink
period to 100 ms and then 800 ms and watching the LED follow.

## Versions this was verified against

| Tool | Version |
| --- | --- |
| Ruby | 4.0.3 |
| GNU g++ (hosted) | 13.3.0 |
| pico-sdk | 1.5.1 |
| arm-none-eabi-g++ | 13.2.Rel1 (ARM official release) |
| cmake | 4.4.0 |
